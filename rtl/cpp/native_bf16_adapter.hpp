#pragma once
#include "component_model.hpp"
#include <Vnative_bf16_adapter.h>
namespace rtx_model { using native_bf16_adapter = ClockedModel<Vnative_bf16_adapter>; }
