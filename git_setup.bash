#! /usr/bin/env bash


cd /PX4-Autopilot-fw/Tools/simulation/gazebo-classic
git remote set-url origin https://github.com/arplaboratory/PX4-SITL_gazebo-classic.git
git fetch
git checkout feature/thermals_ros2


