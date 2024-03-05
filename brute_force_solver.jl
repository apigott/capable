### A Pluto.jl notebook ###
# v0.19.27

using Markdown
using InteractiveUtils

# ╔═╡ 0887602f-3361-4ccc-bd2d-995720a27863
begin
	using Pkg
	Pkg.activate("working")
end

# ╔═╡ 72ec0c70-5549-11ed-3e52-2d9e3f8e20cb
begin
	import JuMP
	import PlutoUI
	using PowerModelsDistribution
	const PMD = PowerModelsDistribution
	import Ipopt
	import Plots
	using StatsBase
	using DataFrames
	using CSV
	using Impute
	using JLD2
	using FileIO
	using LinearAlgebra
end

function build_mn_mc_opf_capc(pm::AbstractUnbalancedPowerModel)
    for (n, network) in nws(pm)
        variable_mc_bus_voltage(pm; nw=n)
        variable_mc_branch_power(pm; nw=n)
        variable_mc_switch_power(pm; nw=n)
        variable_mc_transformer_power(pm; nw=n)
        variable_mc_generator_power(pm; nw=n)
        variable_mc_load_power(pm; nw=n)
        variable_mc_storage_power(pm; nw=n) # missing from capc
		variable_mc_capcontrol(pm; nw=n, relax=true)

        constraint_mc_model_voltage(pm; nw=n)

        for i in ids(pm, n, :ref_buses)
            constraint_mc_theta_ref(pm, i; nw=n)
        end

        for id in ids(pm, n, :gen)
            constraint_mc_generator_power(pm, id; nw=n)
        end

        for id in ids(pm, n, :load)
            constraint_mc_load_power(pm, id; nw=n)
        end

        for i in ids(pm, n, :bus)
            constraint_mc_power_balance_capc(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            constraint_storage_complementarity_nl(pm, i; nw=n)
            constraint_mc_storage_losses(pm, i; nw=n)
            constraint_mc_storage_thermal_limit(pm, i; nw=n)
        end

        for i in ids(pm, n, :branch)
            constraint_mc_ohms_yt_from(pm, i; nw=n)
            constraint_mc_ohms_yt_to(pm, i; nw=n)
            constraint_mc_voltage_angle_difference(pm, i; nw=n)
            constraint_mc_thermal_limit_from(pm, i; nw=n)
            constraint_mc_thermal_limit_to(pm, i; nw=n)
            constraint_mc_ampacity_from(pm, i; nw=n)
            constraint_mc_ampacity_to(pm, i; nw=n)
        end

        for i in ids(pm, n, :switch)
            constraint_mc_switch_state(pm, i; nw=n)
            constraint_mc_switch_thermal_limit(pm, i; nw=n)
            constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            constraint_mc_transformer_power(pm, i; nw=n)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        constraint_storage_state(pm, i; nw=n_1)
    end

    for n_2 in network_ids[2:end]
        for i in ids(pm, :storage; nw=n_2)
            constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_mc_min_fuel_cost(pm)
end

# ╔═╡ 150ca601-5bce-4eec-9c9f-1fe1ac428ce0
data_eng = PMD.parse_file(
	# "123Bus/IEEE123Master.dss",
	"13Bus/IEEE13Nodeckt.dss",
	# "lvtestcase_notrans.dss",
	# "../PowerModelsDistribution.jl/test/data/opendss/IEEE13_CapControl.dss",
	transformations=[PMD.remove_all_bounds!]
);

line2bus = Dict([line=>data["t_bus"] for (line, data) in data_eng["line"]])
line2bus2 = Dict([line=>data["f_bus"] for (line, data) in data_eng["line"]])
bus2line = Dict([bus=>line for (line, bus) in line2bus])
bus2line2 = Dict([bus=>line for (line, bus) in line2bus2])
bus2line = merge!(bus2line, bus2line2)

# ╔═╡ 49c3e05d-e066-4d43-81eb-7388ce00590e
begin
	timestamps = collect(0:1:240) # timestamps
	D_k = timestamps[2:end].-timestamps[1:end-1] # duration of each timestep
	K = 1:length(D_k) # set of timesteps
end;

df = CSV.read("annual_data.csv", DataFrame)

# ╔═╡ cb07cc10-e7f8-456f-bbc6-8b0e7ad5aaeb
data_eng["time_series"] = Dict{String, Any}()
for name in names(df)
	if name != "Timestamp"
		data_eng["time_series"][name] = Dict{String, Any}(
			"replace" => false,
			"time" => K,
			"values" => 0.5*df[!,name]
			# "values" => cos.((pi/2/maximum(K)).*K)
		)
	end
end

# attach a reference to each load, so that the consumption will be scaled
# by the profile we created
for (name,load) in data_eng["load"]
	load["pd"]=1
	load["qd"]=0.45
	load["time_series"] = Dict(
		"pd_nom"=>load["bus"],
		"qd_nom"=>load["bus"]
	)
end

for m in 1:n_buses
	for n in (m+1):n_buses
		# setup
		selected_buses = [all_buses[m], all_buses[n]]
		data_eng["shunt"] = Dict{String, Any}()
		for bus in selected_buses
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
		# solve
		data_math_mn = transform_data_model(data_eng; multinetwork=true)
		pm = instantiate_mc_model(data_math_mn, ACPUPowerModel, build_mn_mc_opf_capc, multinetwork=true);
		res = optimize_model!(pm, optimizer=Ipopt.Optimizer)
		save("bruteforce/"*selected_buses[1]*"_"*selected_buses[2]*".jld2", "data", res)
	end
end
