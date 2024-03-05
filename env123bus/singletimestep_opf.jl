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

function run_123bus_opf(locations::Vector{Int64},myloads::Vector{Float64})
    # case_file =  "../123Bus/Run_IEEE123Bus.DSS"
    frac = 1
    case_file =  "../123Bus/IEEE123Master.dss"
    data_eng = PMD.parse_file(case_file, transformations=[PMD.remove_all_bounds!])

    PMD.reduce_lines!(data_eng) # Kron reduction to omit the neutral

    data_eng["settings"]["sbase_default"] = 1.0*1E3/data_eng["settings"]["power_scale_factor"]

    # creating an empty dict serves the purpose of clearing out existing
    # components from DSS and/or initializing a set of that component type
    data_eng["storage"] = Dict{String, Any}()


    for (_, load) in data_eng["load"]
        x = pop!(myloads) * 0.1
        for i in 1:length(load["pd_nom"])
            # sf = rand([0.35,0.6])
            sf = 0.45
			load["pd_nom"][i] = x * 1.0 * sf
            # qscale = rand([0.35,0.6])
            qscale = 0.5
			load["qd_nom"][i] = x * qscale * sf
		end
	end

    line2bus = Dict([line=>data["t_bus"] for (line, data) in data_eng["line"]])
	line2bus2 = Dict([line=>data["f_bus"] for (line, data) in data_eng["line"]])
	bus2line = Dict([bus=>line for (line, bus) in line2bus])
	bus2line2 = Dict([bus=>line for (line, bus) in line2bus2])
	bus2line = merge!(bus2line, bus2line2)

    # println([k for (k,v) in bus2line][begin:frac:end])
#     bus_shuffle = ["100",
# "48",
# "50",
# "66",
# "10",
# "75",
# "52",
# "106",
# "67",
# "4",
# "51",
# "86",
# "88",
# "44",
# "81",
# "43",
# "9r",
# "24",
# "33",
# "71",
# "2",
# "42",
# "97",
# "151",
# "49",
# "23",
# "9",
# "450",
# "101",
# "7",
# "102",
# "150r",
# "35",
# "22",
# "57",
# "109",
# "5",
# "37",
# "64",
# "110",
# "14",
# "78",
# "84",
# "55",
# "85",
# "65",
# "40",
# "82",
# "31",
# "53",
# "38",
# "103",
# "45",
# "13",
# "93",
# "39",
# "105",
# "114",
# "20",
# "160",
# "108",
# "21",
# "27",
# "26",
# "300",
# "77",
# "91",
# "41",
# "79",
# "74",
# "69",
# "6",
# "16",
# "61",
# "73",
# "80",
# "63",
# "47",
# "12",
# "19",
# "15",
# "59",
# "11",
# "98",
# "3",
# "36",
# "68",
# "25",
# "197",
# "90",
# "62",
# "107",
# "87",
# "83",
# "29",
# "56",
# "92",
# "46",
# "89",
# "34",
# "104",
# "160r",
# "28",
# "54",
# "112",
# "17",
# "60",
# "111",
# "135",
# "30",
# "250",
# "25r",
# "72",
# "70",
# "8",
# "61s",
# "96",
# "99",
# "32",
# "94",
# "113",
# "1",
# "58",
# "95",
# "18",
# "76"]
#     bus_district = ["9",
# "23",
# "27",
# "17",
# "26",
# "3",
# "12",
# "14",
# "20",
# "4",
# "32",
# "8",
# "25r",
# "22",
# "250",
# "29",
# "33",
# "21",
# "1",
# "10",
# "18",
# "31",
# "150r",
# "24",
# "9r",
# "15",
# "2",
# "25",
# "7",
# "19",
# "11",
# "5",
# "30",
# "28",
# "16",
# "13",
# "6",
# "42",
# "48",
# "35",
# "49",
# "36",
# "45",
# "44",
# "47",
# "39",
# "40",
# "151",
# "51",
# "135",
# "46",
# "43",
# "41",
# "38",
# "34",
# "37",
# "50",
# "57",
# "54",
# "55",
# "160r",
# "64",
# "52",
# "58",
# "61",
# "62",
# "66",
# "53",
# "60",
# "59",
# "63",
# "160",
# "61s",
# "56",
# "65",
# "92",
# "84",
# "82",
# "78",
# "83",
# "80",
# "96",
# "73",
# "97",
# "450",
# "69",
# "85",
# "94",
# "81",
# "89",
# "70",
# "93",
# "67",
# "98",
# "76",
# "79",
# "68",
# "88",
# "86",
# "90",
# "71",
# "74",
# "87",
# "99",
# "77",
# "72",
# "91",
# "100",
# "95",
# "108",
# "110",
# "101",
# "105",
# "197",
# "300",
# "102",
# "109",
# "106",
# "111",
# "113",
# "104",
# "103",
# "114",
# "112",
# "107"]
    # all_buses = bus_district[begin:frac:end]
    all_buses = sort!([k for (k,v) in bus2line])[begin:frac:end]
    # here we initialize capacitor bank data and provide some cap bank values
    # if baseline != true
    data_eng["shunt"] = Dict{String, Any}()
	# for idx in locations
    #     bus = all_buses[idx]
    #     data_eng["shunt"]["cap_$bus"] = Dict{String, Any}(
	# 		"bus"=>bus,
	# 		"connections"=>[x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 		"gs"=>zeros(length([x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]]),length([x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]])),
	# 		"bs"=>diagm(ones(length([x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]]))).*0.012*length([x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]]),
	# 		"model"=>CAPACITOR,
	# 		"dispatchable"=>YES,
	# 		"status"=>ENABLED,
	# 		"controls"=>Dict{String, Any}(
	# 			"type"=>["current" for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 			"element"=>"line."*bus2line[bus],
	# 			"terminal"=>[x for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 			"onsetting"=>[300 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 			"offsetting"=>[200 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 			"voltoverride"=>[false for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 			"ptratio"=>[60 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 			"ctratio"=>[60 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 			"vmin"=>[115 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]],
	# 			"vmax"=>[126 for x in data_eng["bus"][bus]["terminals"] if x in [1,2,3]]
	# 		)
	# 	)
	# end
    # end

    # solve_mn_mc_opf for timelinked OPFs
    res = solve_mc_opf(data_eng, IVRUPowerModel, Ipopt.Optimizer, setting=Dict("output"=>Dict("duals"=>true)));
    # loadps = [res["solution"]["load"]["load$l"]["pd"][1] for l in collect(1:55)]
    # load_buses = [data_eng["load"]["load$l"]["bus"] for l in collect(1:55)]
    # lam = [Statistics.mean(res["solution"]["bus"][i]["lam_kcl_r"]) for i in load_buses]
    # socs = [res["solution"]["storage"]["EV_stor_$e"]["se"] for e in EVs]
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
