# from batt_env import BattPlacement
import batt_env
from stable_baselines3 import PPO
import os
import string

env = batt_env.BattPlacement13Bus()

# prev_files = os.listdir('agents')
# if len(prev_files) > 0:
#     recent_vers = max([int(file[-7]) for file in prev_files])

for minor in string.ascii_lowercase[:3]:
    obs = env.reset()
    model = PPO.load(f"agents/batt-placement-v{1}-{minor}")
    total_reward = 0
    for t in range(200):
        a = model.predict(obs)[0]
        # print(a)
        obs, reward, done, info = env.step(a)
        total_reward += reward

    print(f"agents/batt-placement-v{1}-{minor}", total_reward)

for minor in string.ascii_lowercase[:3]:
    env.reset()
    total_reward = 0
    for t in range(200):
        a = env.action_space.sample()
        obs, reward, done, info = env.step(a)
        total_reward += reward
