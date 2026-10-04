#pragma once
#include "component_model.hpp"
#include <Vblock_allocator.h>
namespace rtx_model { using block_allocator = ClockedModel<Vblock_allocator>; }
