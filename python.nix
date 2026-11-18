{ config, pkgs, lib, ... }:

let
  pythonWithAiRPackages = pkgs.python313.withPackages (ps: with ps; [
    # Core tooling
    pip
    virtualenv
    setuptools
    wheel
    ipython
    jupyterlab

    # Formatting, typing, testing and debugging
    black
    debugpy
    mypy
    pytest
    ruff

    # Scientific computing and data analysis
    numpy
    scipy
    sympy
    pandas
    networkx
    scikit-fuzzy
    statsmodels

    # Plots and notebooks
    matplotlib
    seaborn
    plotly

    # Optimization, control and robotics
    casadi
    control
   # ortools
   # pinocchio

    # GUI and games
   # pyqt5
   # tkinter
   # pygame

    # Images, vision and hardware communication
    pillow
   # opencv4
    scikit-image
    pyserial
    pyusb

    # Everyday project helpers
    pyyaml
    requests
    rich
    tqdm
  ]);
in
{
  environment.systemPackages = with pkgs; [
    # lib.hiPrio: programs_minimal.nix instaluje gołe `python3` (bin/python3 koliduje
    # z tym wrapperem o tym samym priorytecie – bez hiPrio wygrywał nieprzewidywalnie
    # goły python3 bez numpy/pyserial/scikit-fuzzy, mimo że full go nadpisuje).
    (lib.hiPrio pythonWithAiRPackages)
    pyright

    # Allows installing and selecting other Python versions per project.
    pyenv

    # Useful when pyenv builds CPython locally.
    bzip2
    libffi
    ncurses
    openssl
    readline
    sqlite
    tk
    xz
    zlib
  ];

  environment.sessionVariables = {
    PYENV_ROOT = "$HOME/.pyenv";
  };

  environment.variables = {
    PYTHON = "${pythonWithAiRPackages}/bin/python";
  };
}
