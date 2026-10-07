// display_attribute.h — the display attributes VietTelex applies to its composition:
//   GUID_DisplayAttributeInput       no underline, no colours (spec §4.2 "không gạch chân")
//   GUID_DisplayAttributeMisspelled  red squiggle, only when Settings::underlineMisspelled
//                                    is on and the composed word cannot be a syllable.
#pragma once
#include "globals.h"

namespace vtx::tip {

// misspelled = the red-squiggle attribute (GUID_DisplayAttributeMisspelled).
HRESULT CreateDisplayAttributeInfo(ITfDisplayAttributeInfo** out, bool misspelled = false);
HRESULT CreateEnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** out);

}  // namespace vtx::tip
