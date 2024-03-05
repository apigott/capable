# activate Julia environement; akin to conda env
using Pkg
Pkg.activate("working")

using PowerModelsDistribution
import Statistics
import Ipopt
import Plots
using Random
using Distributions
using LinearAlgebra

const PMD = PowerModelsDistribution

function run_13bus_opf(locations::Vector{Int64},myloads::Vector{Float64})
    case_file = "../13Bus/IEEE13Nodeckt.dss"
    data_eng = PMD.parse_file(case_file, transformations=[PMD.remove_all_bounds!])

    PMD.reduce_lines!(data_eng) # Kron reduction to omit the neutral

    data_eng["settings"]["sbase_default"] = 1.0*1E3/data_eng["settings"]["power_scale_factor"]

    # creating an empty dict serves the purpose of clearing out existing
    # components from DSS and/or initializing a set of that component type
    data_eng["storage"] = Dict{String, Any}()

    for (_, load) in data_eng["load"]
        x = pop!(myloads)
        for i in 1:length(load["pd_nom"])
            # sf = 0.5#rand([0.35,0.6])
            sf = rand([0.35,0.6])
            qrand = rand([0.3,0.5])
			load["pd_nom"][i] = x * 1.0 * sf
			load["qd_nom"][i] = x * qrand * sf
		end
	end

    line2bus = Dict([line=>data["t_bus"] for (line, data) in data_eng["line"]])
	line2bus2 = Dict([line=>data["f_bus"] for (line, data) in data_eng["line"]])
	bus2line = Dict([bus=>line for (line, bus) in line2bus])
	bus2line2 = Dict([bus=>line for (line, bus) in line2bus2])
	bus2line = merge!(bus2line, bus2line2)

    all_buses = sort!([k for (k,v) in bus2line])
    # unsorted used for <= v3
    # here we initialize capacitor bank data and provide some cap bank values
    # if baseline != true
    data_eng["shunt"] = Dict{String, Any}()
	for idx in locations # index of bus selected out of all selected locations
        bus = all_buses[idx]
        data_eng["shunt"]["cap_$bus"] = Dict{String, Any}(
			"bus"=>bus,
			"connections"=>[x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
			"gs"=>zeros(length([x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]]),length([x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]])),
			"bs"=>diagm(ones(length([x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]]))).*0.012*length([x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]]),
			"model"=>CAPACITOR,
			"dispatchable"=>YES,
			"status"=>ENABLED,
			"controls"=>Dict{String, Any}(
				"type"=>["current" for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
				"element"=>"line."*bus2line[bus],
				"terminal"=>[x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
				"onsetting"=>[300 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
				"offsetting"=>[200 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
				"voltoverride"=>[false for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
				"ptratio"=>[60 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
				"ctratio"=>[60 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
				"vmin"=>[115 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
				"vmax"=>[126 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]]
			)
		)
	end
    # end

    # solve_mn_mc_opf for timelinked OPFs
    res = solve_mc_opf(data_eng, IVRUPowerModel, Ipopt.Optimizer, setting=Dict("output"=>Dict("duals"=>true)));
    all_load_names = [k for (k,v) in data_eng["load"]]
    data_math = transform_data_model(data_eng)
    vm_pu = fill(NaN, length(data_eng["load"]))
	for  l in 1:length(data_eng["load"])
		load = all_load_names[l]
		bus_id = data_eng["load"][load]["bus"]
		bus_ind = data_math["bus_lookup"][bus_id]
		sol_bus = res["solution"]["bus"][bus_id]
		data_bus = data_eng["bus"][bus_id]
		vbase = data_math["bus"]["$bus_ind"]["vbase"]
		phase = data_eng["load"][load]["connections"][1]
		ind = findfirst(data_bus["terminals"].==phase)
		vm_pu[l] = abs(sol_bus["vr"][ind]+im*sol_bus["vi"][ind])/vbase
	end

    return res, vm_pu #Dict{String, Any}("p_load"=>loadps, "dual_var"=>lam)
end
