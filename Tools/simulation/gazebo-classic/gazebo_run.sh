#!/usr/bin/env bash
set -e

if [ "$#" -lt 6 ]; then
	echo usage: sitl_run.sh sitl_bin debugger model world src_path build_path
	exit 1
fi

if [[ -n "$DONT_RUN" ]]; then
	echo "Not running simulation (DONT_RUN is set)."
	exit 0
fi

sitl_bin="$1"  #/home/luca/PX4-Autopilot/build/px4_sitl_default/bin/px4
debugger="$2"  #none
model="$3" #plane
world="$4" #none or windy
src_path="$5" #/home/luca/PX4-Autopilot
build_path="$6"  #/home/luca/PX4-Autopilot/build/px4_sitl_default

echo SITL ARGS

echo sitl_bin: $sitl_bin
echo debugger: $debugger
echo model: $model
echo world: $world
echo src_path: $src_path
echo build_path: $build_path

rootfs="$build_path/rootfs" # this is the working directory
mkdir -p "$rootfs"

# To disable user input
if [[ -n "$NO_PXH" ]]; then
	no_pxh=-d
else
	no_pxh=""
fi

# To disable user input
if [[ -n "$VERBOSE_SIM" ]]; then
	verbose="--verbose"
else
	verbose=""
fi

# Disable follow mode
if [[ "$PX4_NO_FOLLOW_MODE" != "1" ]]; then
    follow_mode="--gui-client-plugin libgazebo_user_camera_plugin.so"
else
    follow_mode=""
fi

# To use gazebo_ros ROS2 plugins
if [[ -n "$ROS_VERSION" ]] && [ "$ROS_VERSION" == "2" ]; then
	ros_args="-s libgazebo_ros_init.so -s libgazebo_ros_factory.so"
else
	ros_args=""
fi

if [ "$model" == "" ] || [ "$model" == "none" ]; then
	echo "empty model, setting iris as default"
	model="iris"
fi

# kill process names that might stil
# be running from last time
pkill -x gazebo || true

export PX4_SIM_MODEL=gazebo-classic_${model}
export PX4_SIM_WORLD=${world}

SIM_PID=0

if [ -x "$(command -v gazebo)" ]; then
	# Get the model name
	model_name="${model}"

	# Set the plugin path so Gazebo finds our model and sim
	source "$src_path/Tools/simulation/gazebo-classic/setup_gazebo.bash" "${src_path}" "${build_path}"
	if [ -z $PX4_SITL_WORLD ]; then
		#Spawn predefined world
		if [ "$world" == "none" ]; then
			if [ -f ${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/worlds/${model}.world ]; then
				echo "empty world, default world ${model}.world for model found"
				world_path="${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/worlds/${model}.world"
			else
				echo "empty world, setting empty.world as default"
				world_path="${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/worlds/empty.world"
			fi
		else
			#Spawn empty world if world with model name doesn't exist
			world_path="${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/worlds/${world}.world"
		fi
	else
		if [ -f ${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/worlds/${PX4_SITL_WORLD}.world ]; then
			# Spawn world by name if exists in the worlds directory from environment variable
			world_path="${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/worlds/${PX4_SITL_WORLD}.world"
		else
			# Spawn world from environment variable with absolute path
			world_path="$PX4_SITL_WORLD"
		fi
	fi
	gzserver $verbose $world_path $ros_args &
	SIM_PID=$!

	# Check all paths in ${GAZEBO_MODEL_PATH} for specified model
	IFS_bak=$IFS
	IFS=":"
	for possible_model_path in ${GAZEBO_MODEL_PATH}; do
		if [ -z $possible_model_path ]; then
			continue
		fi
		# trim \r from path
		possible_model_path=$(echo $possible_model_path | tr -d '\r')
		if test -f "${possible_model_path}/${model}/${model}.sdf" ; then
			modelpath=$possible_model_path
			break
		fi
	done
	IFS=$IFS_bak

	if [ -z $modelpath ]; then
		echo "Model ${model} not found in model path: ${GAZEBO_MODEL_PATH}"
		exit 1
	else
		echo "Using: ${modelpath}/${model}/${model}.sdf"
	fi

	while gz model --verbose --spawn-file="${modelpath}/${model}/${model_name}.sdf" --model-name=${model} -x 1.01 -y 0.98 -z 0.83 -Y 1.7 2>&1 | grep -q "An instance of Gazebo is not running."; do
		echo "gzserver not ready yet, trying again!"
		sleep 1
	done

	if [[ -n "$HEADLESS" ]]; then
		echo "not running gazebo gui"
	else
		# gzserver needs to be running to avoid a race. Since the launch
		# is putting it into the background we need to avoid it by backing off
		sleep 3
		nice -n 20 gzclient --verbose $follow_mode &
		GUI_PID=$!
	fi
else
	echo "You need to have gazebo simulator installed!"
	exit 1
fi


