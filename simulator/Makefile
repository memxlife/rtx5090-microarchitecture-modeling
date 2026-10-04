CXX ?= c++
CXXFLAGS ?= -O3 -std=c++20 -pthread
HEADERS := $(wildcard src/*.hpp)

all: build/full_gpu_parallel

build/full_gpu_parallel: src/full_gpu_parallel.cpp $(HEADERS)
	mkdir -p build
	$(CXX) $(CXXFLAGS) -Isrc src/full_gpu_parallel.cpp -o $@

smoke: all
	python3 validate.py

full: all
	python3 validate.py --full

clean:
	rm -rf build

.PHONY: all smoke full clean
