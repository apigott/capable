from julia.api import Julia

print("activating julia")
jl = Julia(compiled_modules=False)
print("adding pkgs")
jl.eval("import Pkg; Pkg.add(\"PowerModelsDistribution\");\
    Pkg.add(\"Distributions\");\
    Pkg.add(\"Plots\");\
    Pkg.add(\"Ipopt\")")
print("evaluating singletimestep_opf")
fn = jl.eval('include("singletimestep_opf.jl")')

import pandas as pd
import gym
import numpy as np


class CapPlacement13Bus(gym.Env):
    def __init__(self):
        self.n_batts = 2
        self.n_buses = 13
        self.observation_space = gym.spaces.Box(np.array([0]), np.array([1]))
        self.action_space = gym.spaces.Box(np.zeros(self.n_buses),np.ones(self.n_buses))
        self.bls = []
        self.df = pd.read_csv("../annual_data.csv")
        self.time = 0
        self.timestep = 0
        self.max_time = len(self.df)
        self.batt_socs = [100.1]*self.n_batts
        self.load_idx = ["634a", "675b", "671", "675a", "652", "670c", "611", "645", "634c", "670b", "634b", "675c", "692", "670a", "646"]
        self.vm_df = pd.DataFrame({})

    def reset(self):
        self.bls = []
        self.vm_df = pd.DataFrame({f'{i}':[1.0] for i in range(1,16)})
        self.time = 0
        return self.get_obs()

    def step(self, action, baseline=False):
        batt_loc = []
        for _ in range(self.n_batts):
            i = np.argmax(action)
            batt_loc += [int(i + 1)]
            action[i] = -1
        if baseline:
            batt_loc = [1,8]
        self.bls += [batt_loc]

        # self.loads = [float(self.df.loc[self.time].tolist()[i]) for i in self.load_idx]
        self.loads = [float(self.df.iloc[self.time][name]) for name in self.load_idx]
        self.time = (self.time+20) % self.max_time
        # try:
        res = fn(batt_loc, self.loads)
        tot_cost = -1*sum([(v-1)**2 for v in res[1]]) #res["p_load"] @ res["dual_var"]
        reward = 40*tot_cost+1#self.get_reward(tot_cost)

        self.vm_df.loc[len(self.vm_df)] = res[1]
        self.timestep += 1
        obs = self.get_obs()

        print(reward)
        return obs, reward, False, {}

    def get_obs(self):
        """a helper function to determine the observation at any point.
        returns the same thing at every instance to aide in making state agnostic
        :return: list of type float/int"""
        return [0]

def env_creator(env_config):
    return CapPlacement13Bus()

if __name__ == "__main__":
    from stable_baselines3 import PPO
    import os
    import string
    from ray.tune.registry import register_env
    training_flag = False
    continue_training = False
    n_test_steps = 240
    env = CapPlacement13Bus()

    env.reset()

    model = PPO("MlpPolicy", env, verbose=1, tensorboard_log='/tmp/ppo/')
    # model = PPO.load(f"agents/cap-placement-v2-e")
    # model.set_env(env)
    prev_files = os.listdir('agents')
    if len(prev_files) > 0:
        next_vers = max([int(prev_files[-1][-7])]) #+ 1
    else:
        next_vers = 0
    if training_flag:
        if continue_training:
            nminors = len([file for file in prev_files if f'cap-placement-v{next_vers}' in file])
        else:
            next_vers += 1
            nminors = 0
        for minor in string.ascii_lowercase[nminors:nminors+5]:
            model.learn(total_timesteps=10000)
            model.save(f"agents/cap-placement-v{next_vers}-{minor}")


    try:
        df = pd.read_csv(f'results-{next_vers}.csv')
    except:
        df = pd.DataFrame()

    for minor in string.ascii_lowercase[0:25]:
        model = PPO.load(f"agents/cap-placement-v{next_vers}-{minor}")
        env = CapPlacement13Bus()
        model.set_env(env)
        total_reward = 0
        rewards = []
        obs = env.reset()
        for t in range(n_test_steps):
            a = model.predict(obs, deterministic=True)[0]
            obs, reward, done, info = env.step(a)
            total_reward += reward
            rewards += [reward]

        print(f"agents/cap-placement-v{next_vers}-{minor}", total_reward)
        for i in range(env.n_batts):
            df[f'{minor}-a{i}'] = [b[i] for b in env.bls]
        df[f'{minor}-r'] = rewards
        df.to_csv(f'results-{next_vers}.csv')
        env.vm_df.to_csv(f'results/voltage-{next_vers}-{minor}.csv')

    try:
        df = pd.read_csv(f'results-{next_vers}.csv')
    except:
        df = pd.DataFrame()

    # model = P
