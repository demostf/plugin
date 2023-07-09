{
  inputs = {
    utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/release-23.05";
    spire.url = "github:spiretf/nix";
    spire.inputs.nixpkgs.follows = "nixpkgs";
    spire.inputs.flake-utils.follows = "utils";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    spire,
  }:
    utils.lib.eachSystem spire.systems (system: let
      overlays = [spire.overlays.default];
      pkgs = (import nixpkgs) {
        inherit system overlays;
      };
      inherit (pkgs) lib;
      curlInclude = pkgs.sourcepawn.buildInclude [./include/cURL.inc ./include/cURL_header.inc];
      spEnv = pkgs.sourcepawn.buildEnv [pkgs.sourcepawn.includes.sourcemod curlInclude];
    in rec {
      packages = {
        plugin = pkgs.buildSourcePawnScript {
          name = "plugin";
          src = ./demostf.sp;
          includes = [curlInclude];
        };
      };
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [spEnv];
      };
    });
}
