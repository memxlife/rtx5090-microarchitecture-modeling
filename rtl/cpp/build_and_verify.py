"""Build and exercise C++ adapters for the linked clocked component sources."""
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CPP = ROOT / "cpp"
SOURCES = sorted((ROOT / "components/library").glob("*.sv"))


def main():
    compiler = shutil.which("verilator")
    if not compiler:
        raise RuntimeError("Verilator is required; no tool installation was attempted")
    results = []
    for module, driver, params, marker in [
        ("timed_queue", "queue_smoke.cpp", ["-GSLOTS=2", "-GLATENCY=4"], "CPP_QUEUE_PASS"),
        ("shared_memory_bank", "shared_smoke.cpp", ["-GLATENCY=3"], "CPP_SHARED_PASS"),
    ]:
        build = CPP / "build" / module
        build.mkdir(parents=True, exist_ok=True)
        command = [compiler, "--cc", "--exe", "--build", "-j", "2", "-Wno-fatal",
                   "--top-module", module, "--Mdir", str(build),
                   "-CFLAGS", f"-std=c++17 -I{CPP}", *params,
                   *map(str, SOURCES), str(CPP / driver)]
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (build / "build.log").write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(f"C++ build failed for {module}; see {build / 'build.log'}")
        start = time.perf_counter()
        tested = subprocess.run([str(build / f"V{module}")], capture_output=True, text=True, timeout=10)
        elapsed = time.perf_counter() - start
        (build / "run.log").write_text(tested.stdout + tested.stderr)
        if tested.returncode or marker not in tested.stdout:
            raise RuntimeError(f"C++ behavior check failed for {module}: {tested.stdout}{tested.stderr}")
        results.append({"module": module, "passed": True, "checks": tested.stdout.strip(),
                        "process_wall_seconds": elapsed, "command": command})
        print(tested.stdout.strip(), flush=True)
    files = SOURCES + [CPP / "component_model.hpp", CPP / "queue_smoke.cpp", CPP / "shared_smoke.cpp"]
    receipt = {"all_passed": True, "implementation": "Verilator-generated C++ with shared clock adapter",
               "results": results, "physical_GPU_timing_validated": False,
               "speed_claim": "Process wall times are smoke-test overhead, not a GEMM simulator speed benchmark.",
               "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    (CPP / "verification.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
