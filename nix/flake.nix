{
  description = "Base/Pro Python environments via Nix";

  inputs = {
    # nixos-25.05 (May 2025): patches CVE-2025-32434 (PyTorch 2.6+), CVE-2025-21587/21502 (JDK 21.0.7+),
    # CVE-2025-48009 (Pillow 11.2.1+), CVE-2025-59268 (NumPy 2.2.6+), Go 1.24.x, Spark 3.5.5+.
    # Python 3.11/3.12/3.13 all in stable; nixpkgs-unstable eliminated.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems       = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [(final: prev: {
              # Disable astropy and pytest-doctestplus tests globally due to numpy compatibility
              python311 = prev.python311.override {
                packageOverrides = pyfinal: pyprev: {
                  pytest-doctestplus = pyprev.pytest-doctestplus.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                };
              };
              python312 = prev.python312.override {
                packageOverrides = pyfinal: pyprev: {
                  pytest-doctestplus = pyprev.pytest-doctestplus.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                };
              };
              python313 = prev.python313.override {
                packageOverrides = pyfinal: pyprev: {
                  pytest-doctestplus = pyprev.pytest-doctestplus.overridePythonAttrs (old: {
                    doCheck = false;
                  });
                };
              };
              # Disable astropy tests at pkgs level to catch transitive deps
              python311Packages = prev.python311Packages.override {
                overrides = pyfinal: pyprev: {
                  astropy = pyprev.astropy.overridePythonAttrs (old: { doCheck = false; });
                };
              };
              python312Packages = prev.python312Packages.override {
                overrides = pyfinal: pyprev: {
                  astropy = pyprev.astropy.overridePythonAttrs (old: { doCheck = false; });
                };
              };
              python313Packages = prev.python313Packages.override {
                overrides = pyfinal: pyprev: {
                  astropy = pyprev.astropy.overridePythonAttrs (old: { doCheck = false; });
                };
              };
            })];
          };

          mkPyEnv = python: pkgsFn: python.withPackages pkgsFn;

          basePackagesFn = ps: with ps; [
            ipython
            numpy
            scipy
            pandas
            scikitlearn
            matplotlib
            seaborn
            pyarrow
            polars
            jupyterlab
            onnxruntime
            opencv4
            pillow
            scikit-image
            fastapi
            uvicorn
            pyspark
          ];

          # catboost: not in nixpkgs (complex Rust build). pip install catboost
          # torch/torchvision/torchaudio/tensorflow/transformers/datasets/tokenizers/
          # sentencepiece/accelerate: installed via pre-built CPU pip wheels in the
          # Packer pro build (scripts/build-pro-envs.sh). Nix compilation of these
          # packages takes hours; pip CPU wheels install in minutes.
          # mlflow/xgboost/lightgbm compile quickly and stay Nix-managed.
          proPackagesFn = ps: basePackagesFn ps ++ (with ps; [
            mlflow
            xgboost
            lightgbm
          ]);
        in {
          py-base       = mkPyEnv pkgs.python311 basePackagesFn;
          py-pro        = mkPyEnv pkgs.python311 proPackagesFn;
          py-base-py312 = mkPyEnv pkgs.python312 basePackagesFn;
          py-pro-py312  = mkPyEnv pkgs.python312 proPackagesFn;
          py-base-py313 = mkPyEnv pkgs.python313 basePackagesFn;
          py-pro-py313  = mkPyEnv pkgs.python313 proPackagesFn;

          python312 = pkgs.python312;
          python313 = pkgs.python313;
          julia     = pkgs.julia-bin or pkgs.julia;
          R         = pkgs.R;
          go        = pkgs.go;
          java      = pkgs.openjdk21;
          spark     = pkgs.spark;
          # Rust: powers tokenizers, polars internals, and ML infra tooling
          rustc     = pkgs.rustc;
          cargo     = pkgs.cargo;
          # Node.js 22 LTS: Jupyter lab extensions, JS-based ML tooling
          nodejs    = pkgs.nodejs_22;

          env-report-base = pkgs.writeShellScriptBin "env-report-base" ''
            "${self.packages.${system}.py-base}/bin/python" -m pip list --format=columns
          '';
          env-report-pro = pkgs.writeShellScriptBin "env-report-pro" ''
            "${self.packages.${system}.py-pro}/bin/python" -m pip list --format=columns
          '';
        }
      );

      apps = forAllSystems (system: {
        jupyter-base = {
          type    = "app";
          program = "${self.packages.${system}.py-base}/bin/jupyter-lab";
        };
        uvicorn-pro = {
          type    = "app";
          program = "${self.packages.${system}.py-pro}/bin/uvicorn";
        };
        env-report-base = {
          type    = "app";
          program = "${self.packages.${system}.env-report-base}/bin/env-report-base";
        };
        env-report-pro = {
          type    = "app";
          program = "${self.packages.${system}.env-report-pro}/bin/env-report-pro";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          languages = pkgs.mkShell {
            packages = [
              pkgs.python311
              pkgs.python312
              pkgs.python313
              self.packages.${system}.py-base
              pkgs.R
              (pkgs.julia-bin or pkgs.julia)
              pkgs.go
              pkgs.openjdk21
              pkgs.rustc
              pkgs.cargo
              pkgs.nodejs_22
            ];
          };
        }
      );
    };
}
