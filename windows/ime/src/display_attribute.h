// display_attribute.h — the one display attribute VietTelex applies to its
// composition: no underline, no colours (spec §4.2 "không gạch chân").
#pragma once
#include "globals.h"

namespace vtx::tip {

HRESULT CreateDisplayAttributeInfo(ITfDisplayAttributeInfo** out);
HRESULT CreateEnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** out);

}  // namespace vtx::tip
