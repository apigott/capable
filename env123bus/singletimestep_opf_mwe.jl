# activate Julia environement; akin to conda env
using Pkg
Pkg.activate("working")

using PowerModelsDistribution
import Statistics
import Ipopt
import Plots
using Random
using Distributions
using StatsBase

const PMD = PowerModelsDistribution

function run_13bus_opf(myloads::Vector{Float64})
    case_file = "../ieee13.dss"
    data_eng = PMD.parse_file(case_file, transformations=[PMD.remove_all_bounds!])

    PMD.reduce_lines!(data_eng) # Kron reduction to omit the neutral

    data_eng["settings"]["sbase_default"] = 1.0*1E3/data_eng["settings"]["power_scale_factor"]

    PMD.add_bus_absolute_vbounds!(data_eng, phase_lb_pu=0.9, phase_ub_pu=1.1, neutral_ub_pu=0.1)

    # creating an empty dict serves the purpose of clearing out existing
    # components from DSS and/or initializing a set of that component type
    data_eng["storage"] = Dict{String, Any}()

    for (_, load) in data_eng["load"]
        x = pop!(myloads)
        load["connections"] = [1,2,3,4]
		load["pd_nom"] = x*[1,1,1]
		load["qd_nom"]= x*rand([0.35,0.6])*[1,1,1]
        # load["timeseries"] = # can add timeseries here for multi timestep OPF
	end

    # sample some random buses to place caps at
	buses = [name for (name, load) in data_eng["bus"]]
	shunt_buses = sample(buses, 2)

    # here we initialize capacitor bank data and provide some cap bank values
    data_eng["shunt"] = Dict{String, Any}()
	for bus in shunt_buses
		data_eng["shunt"][bus] = Dict{String, Any}(
			"bus"=>bus,
			"connections"=>[1,2,3],
			"gs"=>[0.0 0.0 0.0;0.0 0.0 0.0;0.0 0.0 0.0],
			"bs"=>[0.0346709 0.0 0.0;0.0 0.0346709 0.0;0.0 0.0 0.0346709],
			"model"=>"CAPACITOR",
			"dispatchable"=>YES, # CAP BANK IS ALWAYS ON UNLESS YOU USE A "controls" component
			"status"=>ENABLED,
            # "controls"=>Dict{String, Any}(
			# 	"type"=>["current", "current", "current"],
			# 	"element"=>"line."*bus2line[bus],
			# 	"terminal"=>[1,2,3],
			# 	"onsetting"=>[300,300,300],
			# 	"offsetting"=>[200,200,200],
			# 	"voltoverride"=>[false, false, false],
			# 	"ptratio"=>[60,60,60],
			# 	"ctratio"=>[60,60,60],
			# 	"vmin"=>[115,115,115],
			# 	"vmax"=>[126,126,126]
			# )
		)
	end

    # solve_mn_mc_opf for timelinked OPFs
    res = solve_mc_opf(data_eng, ACPUPowerModel, Ipopt.Optimizer, setting=Dict("output"=>Dict("duals"=>true)));

    loadps = [res["solution"]["load"]["load$l"]["pd"][1] for l in collect(1:55)]
    load_buses = [data_eng["load"]["load$l"]["bus"] for l in collect(1:55)]
    lam = [Statistics.mean(res["solution"]["bus"][i]["lam_kcl_r"]) for i in load_buses]
    # socs = [res["solution"]["storage"]["EV_stor_$e"]["se"] for e in EVs]
    return Dict{String, Any}("p_load"=>loadps, "dual_var"=>lam)
end
