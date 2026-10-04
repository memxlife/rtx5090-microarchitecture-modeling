#pragma once
#include "component_model.hpp"
#include <Vgemm_tile_controller.h>
namespace rtx_model { using gemm_tile_controller = ClockedModel<Vgemm_tile_controller>; }
