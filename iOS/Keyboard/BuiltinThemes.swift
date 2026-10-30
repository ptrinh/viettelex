// Sinh bởi Scripts/gen-builtin-themes.py từ themes/builtin-themes.json — KHÔNG sửa tay.
// Theme có sẵn (trừ Hệ thống / Kính — vẽ theo nền tảng) dạng JSON, đọc một lần (BuiltinThemes.specs).
enum BuiltinThemesData {
    static let json = ##"""
{
  "v": 1,
  "themes": [
    {
      "v": 1, "id": "oled", "name": {"vi": "Tối OLED", "en": "OLED Dark"},
      "light": {"bg": "#000000", "key": "#1C1C1E", "special": "#3A3A3C", "ink": "#FFFFFF",
                "accent": "#0A84FF", "balloon": "#2C2C2E", "trail": "#99FFFFFF"},
      "dark": "same"
    },
    {
      "v": 1, "id": "contrast", "name": {"vi": "Tương phản cao", "en": "High Contrast"},
      "light": {"bg": "#000000", "key": "#141414", "special": "#4D4D4D", "ink": "#FFFFFF",
                "accent": "#FFD60A", "border": "#D8FFFFFF", "trail": "#FFD60A"},
      "dark": "same"
    },
    {
      "v": 1, "id": "peach", "name": {"vi": "Hồng đào", "en": "Peach"},
      "light": {"bg": "#FBE3E1", "key": "#FFF8F7", "special": "#F1C4BF", "ink": "#4A2226", "accent": "#C2505A"},
      "dark": {"bg": "#2A1A1C", "key": "#45292D", "special": "#5C3A3F", "ink": "#FBE3E1", "accent": "#C2505A"}
    },
    {
      "v": 1, "id": "mint", "name": {"vi": "Bạc hà", "en": "Mint"},
      "light": {"bg": "#D9F2E7", "key": "#F6FFFA", "special": "#AFDDC9", "ink": "#173B30", "accent": "#1F7A5C"},
      "dark": {"bg": "#10241D", "key": "#1D3B30", "special": "#2A5244", "ink": "#D9F2E7", "accent": "#1F7A5C"}
    },
    {
      "v": 1, "id": "sky", "name": {"vi": "Trời xanh", "en": "Sky"},
      "light": {"bg": "#DAE9F8", "key": "#F6FAFF", "special": "#B3CFEE", "ink": "#14304C", "accent": "#2C6BB8"},
      "dark": {"bg": "#111E2E", "key": "#1E324A", "special": "#2B4566", "ink": "#DAE9F8", "accent": "#2C6BB8"}
    },
    {
      "v": 1, "id": "lavender", "name": {"vi": "Oải hương", "en": "Lavender"},
      "light": {"bg": "#E8E2F6", "key": "#FBF9FF", "special": "#CBBFEA", "ink": "#2C2345", "accent": "#6A48C4"},
      "dark": {"bg": "#1C1830", "key": "#2E2848", "special": "#403862", "ink": "#E8E2F6", "accent": "#6A48C4"}
    },
    {
      "v": 1, "id": "blackHeart", "name": {"vi": "Tim đen", "en": "Black Heart"},
      "light": {"bg": "#000000", "key": "#1A1A1A", "special": "#333333", "ink": "#FFFFFF", "accent": "#E63E7A",
                "deco": {"motif": "hearts", "color": "#8CFF6FA3"}},
      "dark": "same"
    },
    {
      "v": 1, "id": "greenFloral", "name": {"vi": "Hoa xanh", "en": "Green Blossom"},
      "light": {"bg": "#EEF6EF", "key": "#FFFFFF", "special": "#DCEEDF", "ink": "#256B42", "accent": "#2E8B57",
                "border": "#4CAF6E", "deco": {"motif": "flowers", "color": "#596DBE8A"}},
      "dark": {"bg": "#0F1D15", "key": "#16291E", "special": "#21392A", "ink": "#9EE0B6", "accent": "#2E8B57",
               "border": "#CC4CAF6E", "deco": {"motif": "flowers", "color": "#474CAF6E"}}
    },
    {
      "v": 1, "id": "sage", "name": {"vi": "Xanh lá", "en": "Sage"},
      "light": {"bg": "#E4EBE2", "key": "#FBFCFA", "special": "#93AB8C", "ink": "#24331F", "accent": "#5E7F55",
                "fn": "#A9BFA3"},
      "dark": {"bg": "#161C15", "key": "#2A3328", "special": "#3A4A36", "ink": "#E4EDE1", "accent": "#5E7F55",
               "fn": "#4A5E45"}
    },
    {
      "v": 1, "id": "neon", "name": {"vi": "Neon", "en": "Neon"}, "swipe": "neon",
      "light": {"bg": "#05080A", "key": "#0E2A2E", "special": "#15393E", "ink": "#5FF5E8", "accent": "#00BFB2",
                "border": "#B200E5D4"},
      "dark": "same"
    },
    {
      "v": 1, "id": "pink", "name": {"vi": "Hồng", "en": "Pink"}, "corner": 70,
      "light": {"bg": "#FCDDE8", "key": "#FFF5F9", "special": "#F6B8CE", "ink": "#5A1F38", "accent": "#D94680"},
      "dark": {"bg": "#2B1520", "key": "#472335", "special": "#5E2F46", "ink": "#FCDDE8", "accent": "#D94680"}
    },
    {
      "v": 1, "id": "tet", "name": {"vi": "Tết", "en": "Lunar New Year"}, "sound": "phao", "effect": "blossom", "swipe": "stardust",
      "light": {"bg": "#8E1010", "key": "#B71C1C", "special": "#7A0D0D", "ink": "#FFD54F", "accent": "#F9A825",
                "accentInk": "#7F0000", "fn": "#9C1414", "fnInk": "#FFCA28", "deco": {"motif": "mai", "color": "#33FFD54F"}},
      "dark": "same"
    },
    {
      "v": 1, "id": "tetMai", "name": {"vi": "Tết mai vàng", "en": "Golden Apricot Tết"}, "sound": "phao", "effect": "blossom", "swipe": "stardust",
      "light": {"bg": "#FFF3D6", "key": "#FFFDF6", "special": "#F3D9A4", "ink": "#7A1414", "accent": "#C62828",
                "fn": "#F6E2B3", "fnInk": "#B71C1C", "deco": {"motif": "mai", "color": "#CCE5A000"}},
      "dark": {"bg": "#2B1608", "key": "#47260F", "special": "#5E3418", "ink": "#FFE6A6", "accent": "#C62828",
               "fn": "#3A1E0C", "fnInk": "#FFC94A", "deco": {"motif": "mai", "color": "#66FFC107"}}
    },
    {
      "v": 1, "id": "xmas", "name": {"vi": "Giáng sinh", "en": "Christmas"}, "sound": "jingle", "effect": "snow", "swipe": "stardust",
      "light": {"bg": "#0B3320", "key": "#17573A", "special": "#0F4229", "ink": "#FFFFFF", "accent": "#D32F2F",
                "fn": "#124A30", "fnInk": "#FFD54F", "deco": {"motif": "snowflake", "color": "#52FFFFFF"}},
      "dark": "same"
    },
    {
      "v": 1, "id": "xmasSnow", "name": {"vi": "Giáng sinh tuyết", "en": "Snowy Christmas"}, "sound": "jingle", "effect": "snow", "swipe": "stardust",
      "light": {"bg": "#E6F1FA", "key": "#FFFFFF", "special": "#C3DAEE", "ink": "#12324F", "accent": "#D32F2F",
                "fn": "#D6E7F5", "fnInk": "#B71C1C", "deco": {"motif": "snowflake", "color": "#996FA8D6"}},
      "dark": {"bg": "#0C1A2C", "key": "#1B2F49", "special": "#28425F", "ink": "#E6F1FA", "accent": "#D32F2F",
               "fn": "#15263D", "fnInk": "#FFD54F", "deco": {"motif": "star", "color": "#66FFD54F"}}
    },
    {
      "v": 1, "id": "piano", "name": {"vi": "Piano", "en": "Piano"}, "sound": "piano",
      "light": {"bg": "#000000", "key": "#FAFAF7", "special": "#85827B", "ink": "#111111", "accent": "#A4161A",
                "fn": "#111111", "fnInk": "#FFFFFF", "border": "#33FFFFFF", "deco": {"motif": "notes", "color": "#66D4AF37"}},
      "dark": "same"
    },
    {
      "v": 1, "id": "sen", "name": {"vi": "Sen Việt", "en": "Vietnamese Lotus"}, "sound": "dantranh", "effect": "petal",
      "light": {"bg": "#FCE4EC", "key": "#FFFFFF", "special": "#F8BBD0", "ink": "#14421A", "accent": "#EC6A9C",
                "accentInk": "#33091C", "fn": "#2E7D32", "fnInk": "#FFFFFF", "deco": {"motif": "lotus", "color": "#66EC6A9C"}},
      "dark": {"bg": "#0D1A11", "key": "#1E3324", "special": "#2E4A35", "ink": "#FCE4EC", "accent": "#EC6A9C",
               "accentInk": "#33091C", "fn": "#15281B", "fnInk": "#F48FB1", "deco": {"motif": "lotus", "color": "#66F48FB1"}}
    },
    {
      "v": 1, "id": "typewriter", "name": {"vi": "Máy chữ cổ", "en": "Vintage Typewriter"}, "corner": 80, "swipe": "brush",
      "font": {"name": "Xanh Mono", "url": "https://viettelex.com/fonts/XanhMono-Regular.ttf",
               "sha256": "f53d8d88b3f35f150c3b4797ab8998afc211d1892b9f8290661cb5fef0bc377e"},
      "sound": "typewriter", "effect": "ink",
      "light": {"bg": "#EFE6D2", "key": "#FBF6E9", "special": "#E3D7BD", "ink": "#3A2A1C", "accent": "#8B3A1E",
                "fn": "#E6DAC1", "fnInk": "#3A2A1C", "border": "#668A7356"},
      "dark": {"bg": "#231B13", "key": "#3A2E22", "special": "#4B3C2C", "ink": "#F3E8D2", "accent": "#8B3A1E",
               "fn": "#2E241A", "fnInk": "#F3E8D2", "border": "#66C9A97C"}
    },
    {
      "v": 1, "id": "rgb", "name": {"vi": "Gaming RGB", "en": "Gaming RGB"}, "corner": 30, "swipe": "rainbow",
      "sound": "mechanical", "effect": "combo",
      "light": {"bg": "#0A0A0F", "key": "#15151C", "special": "#1F1F28", "ink": "#F2F2F7", "accent": "#7C4DFF",
                "fn": "#101016", "fnInk": "#E0E0EA", "borderFx": "rainbow"},
      "dark": "same"
    },
    {
      "v": 1, "id": "space", "name": {"vi": "Vũ trụ", "en": "Outer Space"}, "sound": "scifi", "effect": "meteor", "swipe": "stardust",
      "light": {"bg": "#070B1E", "key": "#141A33", "special": "#1C2445", "ink": "#E8ECFF", "accent": "#3D5AFE",
                "fn": "#10162C", "fnInk": "#B8C4FF",
                "deco": {"motif": "starfield", "color": "#5CFFFFFF", "density": 140}},
      "dark": "same"
    },
    {
      "v": 1, "id": "trungthu", "name": {"vi": "Trung Thu", "en": "Mid-Autumn"}, "sound": "trong", "effect": "lantern",
      "light": {"bg": "#0B1636", "key": "#1A2A57", "special": "#13214A", "ink": "#FFF1D0", "accent": "#F59E2B",
                "accentInk": "#2B1300", "fn": "#142352", "fnInk": "#FFC857",
                "deco": {"motif": "lantern", "alt": "moon", "color": "#73FFB347"}},
      "dark": "same"
    },
    {
      "v": 1, "id": "valentine", "name": {"vi": "Valentine", "en": "Valentine"}, "sound": "pop", "effect": "heart",
      "light": {"bg": "#FFE3E8", "key": "#FFFFFF", "special": "#FFC2CF", "ink": "#9B1035", "accent": "#D81B4A",
                "fn": "#FFD3DC", "fnInk": "#B0123D", "deco": {"motif": "hearts", "color": "#4DE8436A"}},
      "dark": {"bg": "#2A0610", "key": "#4E0D20", "special": "#6B1430", "ink": "#FFE9EE", "accent": "#D81B4A",
               "fn": "#3D0918", "fnInk": "#FF9AB5", "deco": {"motif": "hearts", "color": "#73FF3D6E"}}
    },
    {
      "v": 1, "id": "halloween", "name": {"vi": "Halloween", "en": "Halloween"}, "sound": "boo", "effect": "smoke", "swipe": "electric",
      "light": {"bg": "#120A1C", "key": "#2A1840", "special": "#1E1030", "ink": "#FFE8CC", "accent": "#FF7A1A",
                "accentInk": "#1A0A00", "fn": "#24123A", "fnInk": "#FF9A3C",
                "deco": {"motif": "pumpkin", "alt": "bat", "color": "#80FF7A1A"}},
      "dark": "same"
    },
    {
      "v": 1, "id": "guitar", "name": {"vi": "Ghi-ta", "en": "Guitar"}, "sound": "guitar", "effect": "string",
      "light": {"bg": "#DDA35C", "key": "#4A2A1C", "special": "#6B4030", "ink": "#F6EBD5", "accent": "#E8A93A",
                "accentInk": "#2A1606", "fn": "#351D13", "fnInk": "#F2C46D",
                "deco": {"motif": "strings", "alt": "inlay", "color": "#D9FBF1DC"}, "spaceDeco": "soundhole"},
      "dark": {"bg": "#1A1009", "key": "#4A2A1C", "special": "#6B4030", "ink": "#F6EBD5", "accent": "#E8A93A",
               "accentInk": "#2A1606", "fn": "#351D13", "fnInk": "#F2C46D",
               "deco": {"motif": "strings", "alt": "inlay", "color": "#73C9A46A"}, "spaceDeco": "soundhole"}
    },
    {
      "v": 1, "id": "mole", "name": {"vi": "Đập chuột", "en": "Whack-a-mole"}, "corner": 80, "sound": "bop", "game": "mole",
      "light": {"bg": "#3D7A24", "key": "#7A4A2A", "special": "#5C3820", "ink": "#FFF4DC", "accent": "#F4C542",
                "accentInk": "#3B2410", "fn": "#5C3820", "fnInk": "#FFE3A3", "border": "#3A2212",
                "deco": {"motif": "flowers", "color": "#73245214"}},
      "dark": "same"
    },
    {
      "v": 1, "id": "neutral", "name": {"vi": "Xám trung tính", "en": "Neutral Grey"},
      "light": {"bg": "#E8EAED", "key": "#FFFFFF", "special": "#D2D5DA", "ink": "#1F1F1F", "accent": "#5F6368"},
      "dark": {"bg": "#202124", "key": "#3C4043", "special": "#2D2E31", "ink": "#E8EAED", "accent": "#9AA0A6",
               "accentInk": "#202124"}
    }
  ]
}
"""##
}
