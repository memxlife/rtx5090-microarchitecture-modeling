#pragma once
#include "component_model.hpp"
#include <Vcoalesced_fp32_warp_store.h>
namespace rtx_model { using coalesced_fp32_warp_store = ClockedModel<Vcoalesced_fp32_warp_store>; }
