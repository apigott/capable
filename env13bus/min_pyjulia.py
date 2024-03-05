# import stuff from Julia
from julia.api import Julia
print("activating julia")
jl = Julia(compiled_modules=False)
print("adding pkgs")
jl.eval("import Pkg; Pkg.add(\"PowerModelsDistribution\");\
    Pkg.add(\"Distributions\");\
    Pkg.add(\"Plots\");\
    Pkg.add(\"Ipopt\")")
print("evaluating singletimestep_opf")
# Julia compiles here so could take a while
# also Julia returns the last thing in the file. currently struggling
# with writing multiple julia funcs in the same .jl and importing all funcs seperately
fn = jl.eval('include("singletimestep_opf_mwe.jl")')

import pandas as pd
import numpy as np

nloads = 50
# i forget how many are in the test case, but the way
# the function is written you can exceed the number of loads
# in the dss file and it uses the first n

loads = list(np.random.uniform(0.5,1.5,nloads))
res = fn(loads)
tot_cost = res["p_load"] @ res["dual_var"]
