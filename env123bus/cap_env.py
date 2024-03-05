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


class CapPlacement123Bus(gym.Env):
    def __init__(self):
        self.n_batts = 4
        self.n_buses = 123
        self.frac = 1
        self.observation_space = gym.spaces.Box(np.array([0]), np.array([1]))
        self.action_space = gym.spaces.Box(np.zeros(int(np.ceil(self.n_buses/self.frac))),np.ones(int(np.ceil(self.n_buses/self.frac))))
        self.bls = []
        # self.df = pd.read_csv("synth_data.csv").drop("Unnamed: 0", axis=1)
        self.df = pd.read_csv("../annual_data123.csv")
        self.time = 0
        self.timestep = 0
        self.max_time = 6720
        self.batt_socs = [100.1]*self.n_batts
        self.load_idx = ["s11a",
"s84c",
"s73c",
"s86b",
"s65a",
"s58b",
"s75c",
"s103c",
"s70a",
"s24c",
"s43b",
"s68a",
"s9a",
"s19a",
"s95b",
"s53a",
"s83c",
"s7a",
"s29a",
"s31c",
"s34c",
"s51a",
"s82a",
"s35a",
"s52a",
"s55a",
"s76c",
"s48",
"s59b",
"s76b",
"s38b",
"s111a",
"s33a",
"s74c",
"s1a",
"s90b",
"s32c",
"s99b",
"s5c",
"s88a",
"s45a",
"s16c",
"s94a",
"s62c",
"s30c",
"s65c",
"s69a",
"s20a",
"s65b",
"s80b",
"s42a",
"s102c",
"s41c",
"s10a",
"s63a",
"s79a",
"s96b",
"s28a",
"s114a",
"s112a",
"s60a",
"s98a",
"s17c",
"s113a",
"s56b",
"s109a",
"s46a",
"s47",
"s66c",
"s2b",
"s100c",
"s49c",
"s76a",
"s12b",
"s6c",
"s64b",
"s77b",
"s87b",
"s37a",
"s85c",
"s4c",
"s71a",
"s22b",
"s49a",
"s104c",
"s49b",
"s50c",
"s107b",
"s39b",
"s106b",
"s92c"]
        self.vm_df = pd.DataFrame({})

    def reset(self):
        self.bls = []
        self.vm_df = pd.DataFrame({f'{i}':[1.0] for i in range(1,92)})
        self.time = 0
        return self.get_obs()

    def step(self, action, baseline=False):
        batt_loc = []
        for _ in range(self.n_batts):
            i = np.argmax(action)
            batt_loc += [int(i + 1)]
            action[i] = -1
        if baseline:
            batt_loc = [112, 117, 120, 122]

        self.bls += [batt_loc]

        self.loads = [float(self.df.iloc[self.time][name]) for name in self.load_idx]
        self.time = (self.time+1) % self.max_time

        res = fn(batt_loc, self.loads)
        tot_cost = -1*sum([(v-1)**2 for v in res[1]])

        self.vm_df.loc[len(self.vm_df)] = res[1]
        self.timestep += 1
        obs = self.get_obs()
        print(tot_cost)
        reward = 40*tot_cost+1
        return obs, reward, False, {}

    def get_obs(self):
        """a helper function to determine the observation at any point.
        returns the same thing at every instance to aide in making state agnostic
        :return: list of type float/int"""
        return [0]

def env_creator(env_config):
    return CapPlacement123Bus()

if __name__ == "__main__":
    from stable_baselines3 import PPO
    import os
    import string
    from ray.tune.registry import register_env
    training_flag = False
    continue_training = True
    n_test_steps = 240
    env = CapPlacement123Bus()

    env.reset()

    model = PPO("MlpPolicy", env, verbose=1, tensorboard_log='/tmp/ppo/')
    # model = PPO.load(f"agents/cap-placement-v2-e")
    # model.set_env(env)
    # if len(prev_files) > 0:
    #     next_vers = max([int(prev_files[-1][-7])]) #+ 1
    # else:
    #     next_vers = 0

    # next_vers=8
    # if training_flag:
    #     if continue_training:
    #         nminors = len([file for file in prev_files if f'cap-placement-v{next_vers}' in file])
    #     else:
    #         next_vers += 1
    #         nminors = 0
    #     for minor in string.ascii_lowercase[nminors:nminors+3]:
    #         model.learn(total_timesteps=10000)
    #         model.save(f"agents-sections/cap-placement-v{next_vers}-{minor}")

    for next_vers in [1]:
        try:
            df = pd.read_csv(f'results-shuffle-det-{next_vers}.csv')
        except:
            df = pd.DataFrame()

        # for minor in string.ascii_lowercase[:10]:
        #     model = PPO.load(f"agents-random/cap-placement-v{next_vers}-{minor}")
        #     env = CapPlacement123Bus()
        #     model.set_env(env)
        #     total_reward = 0
        #     rewards = []
        #     obs = env.reset()
        #     for t in range(n_test_steps):
        #         a = model.predict(obs)[0]
        #         obs, reward, done, info = env.step(a)
        #         total_reward += reward
        #         rewards += [reward]
        #
        #     for i in range(env.n_batts):
        #         df[f'{minor}-a{i}'] = [b[i] for b in env.bls]
        #     df[f'{minor}-r'] = rewards
        #     df.to_csv(f'results-shuffle-det-{next_vers}.csv')
        #     env.vm_df.to_csv(f'results-shuffle/voltage-{next_vers}-{minor}.csv')

        try:
            df = pd.read_csv(f'results-det-{next_vers}.csv')
        except:
            df = pd.DataFrame()

        model = PPO.load(f"agents-random/cap-placement-v{next_vers}-{'j'}")
        # for minor in ['top']:
        #     env.reset()
        #     total_reward = 0
        #     rewards = []
        #
        #     for t in range(n_test_steps):
        #         avg_action = model.predict([0], deterministic=True)[0]
        #         obs, reward, done, info = env.step(avg_action)
        #         total_reward += reward
        #         rewards += [reward]
        #
        #     for i in range(env.n_batts):
        #         df[f'{minor}-a{i}'] = [b[i] for b in env.bls]
        #     df[f'{minor}-r'] = rewards
        #     df.to_csv(f'results-shuffle-det-{next_vers}.csv')
        #     env.vm_df.to_csv(f'results-shuffle/voltage-{next_vers}-{minor}.csv')

        for minor in ['baseline']:
            env.reset()
            total_reward = 0
            rewards = []
            for t in range(n_test_steps):
                a = env.action_space.sample()
                obs, reward, done, info = env.step(a, baseline=True)
                total_reward += reward
                rewards += [reward]

            for i in range(env.n_batts):
                df[f'{minor}-a{i}'] = [b[i] for b in env.bls]
            df[f'{minor}-r'] = rewards
            df.to_csv(f'results-det-{next_vers}.csv')
            env.vm_df.to_csv(f'results-det/voltage-{next_vers}-{minor}.csv')

        # for minor in ['none']:
        #     env.reset()
        #     total_reward = 0
        #     rewards = []
        #     for t in range(n_test_steps):
        #         a = env.action_space.sample()
        #         obs, reward, done, info = env.step(a, baseline=True)
        #         total_reward += reward
        #         rewards += [reward]
        #
        #     for i in range(env.n_batts):
        #         df[f'{minor}-a{i}'] = [b[i] for b in env.bls]
        #     df[f'{minor}-r'] = rewards
        #     df.to_csv(f'results-det-{next_vers}.csv')
        #     env.vm_df.to_csv(f'results-det/voltage-{next_vers}-{minor}.csv')
