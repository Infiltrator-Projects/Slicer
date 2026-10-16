#pragma once

#include <wx/font.h>
#include <wx/settings.h>

namespace Slic3r::GUI::ProductTypography {
inline constexpr const char* ui_family = "MB Corpo S Title WEB";
inline constexpr const char* title_family = "MB Corpo A Title Cond WEB";
inline constexpr const char* regular_file = "mb-corpo-s-regular.ttf";

inline wxFont with_ui_face(wxFont font)
{
    font.SetFaceName(wxString::FromUTF8(ui_family));
    return font;
}

inline wxFont ui_font()
{
    return with_ui_face(wxSystemSettings::GetFont(wxSYS_DEFAULT_GUI_FONT));
}
}
