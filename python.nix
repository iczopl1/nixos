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
    ortools
   # pinocchio

    # GUI and games
   # pyqt5
   # tkinter
    pygame

    # Images, vision and hardware communication
    pillow
   # opencv4
    scikit-image
    pyserial
    pyusb

    # Everyday project helpers
    paramiko
    scp
    pyyaml
    requests
    rich
    tqdm
  ]);

  # Dodatkowe wersje Pythona (3.11, 3.12) z nixpkgs. Nixpkgs w tym kanale NIE ma już
  # python310 (zdjęte z 26.05) – stąd tylko dwie, nie trzy wersje; 3.13 (domyślna,
  # pythonWithAiRPackages wyżej) i tak pokrywa resztę.
  # Zestaw pakietów dobrany dry-buildem (MASTER §4 – sprawdzian przed commitem):
  # numpy/pip = z cache, sekundy (jedyne lokalne buildy to trywialne wrappery env).
  # pandas dodaje lokalny build cython+pandas (realne minuty – te dwie wersje
  # Pythona nie są tu domyślne, więc nixpkgs nie ma dla nich tak gotowego cache jak
  # dla 3.13), scipy +34 buildy (pythran), matplotlib +39 (fonty/backendy) – żadnej
  # z tych trzech nie dodano, żeby `python3.11`/`python3.12` faktycznie stawały się
  # dostępne "od razu", a nie po kompilacji. Dopisać ręcznie, jeśli kiedyś potrzebne.
  pyExtraPkgs = ps: with ps; [ pip numpy ];
  python311Full = pkgs.python311.withPackages pyExtraPkgs;
  python312Full = pkgs.python312.withPackages pyExtraPkgs;

  # Tylko binarka z wersją w nazwie (python3.11/python3.12) – `.withPackages` sam
  # eksportuje też gołe `python3`/`python`, co kolidowałoby z python313 (hiPrio
  # niżej) i między sobą (3.11 vs 3.12 na tej samej, domyślnej, priorytecie).
  versionedPythonBin =
    ver: drv:
    pkgs.runCommand "python${ver}-versioned" { } ''
      mkdir -p $out/bin
      ln -s ${drv}/bin/python${ver} $out/bin/python${ver}
    '';
in
{
  environment.systemPackages = with pkgs; [
    # lib.hiPrio: programs_minimal.nix instaluje gołe `python3` (bin/python3 koliduje
    # z tym wrapperem o tym samym priorytecie – bez hiPrio wygrywał nieprzewidywalnie
    # goły python3 bez numpy/pyserial/scikit-fuzzy, mimo że full go nadpisuje).
    (lib.hiPrio pythonWithAiRPackages)
    pyright

    (versionedPythonBin "3.11" python311Full)
    (versionedPythonBin "3.12" python312Full)

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
