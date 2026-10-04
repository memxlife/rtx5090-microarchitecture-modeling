#pragma once
#include "component_model.hpp"
#include <Vtransaction_queue.h>
namespace rtx_model { using transaction_queue = ClockedModel<Vtransaction_queue>; }
