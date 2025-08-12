export PYTHON=python3
export PIP=pip3
export PENV=$(pwd)/venv
$PYTHON -m venv $PENV
source $PENV/bin/activate
$PIP install --upgrade pip
$PIP install numpy
$PIP install torch
deactivate
