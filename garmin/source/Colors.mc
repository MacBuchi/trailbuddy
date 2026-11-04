import Toybox.Lang;

//! Die Farben der Uhr: je die nächste der 64 MIP-Farben (CIELAB) zur
//! Kartenfarbe der App (`lib/core/app_colors.dart`, heller Satz — die
//! Karte ist immer hell, also auch hier der Grund weiß).
//! `tool/garmin_route.py --self-test` rechnet das nach; geprüft wird
//! außerdem am Gerät in der Sonne (Konzept-Garmin 8.4).
module TbColors {
    const GROUND = 0xFFFFFF;    // halo / Grund
    const TEXT = 0x000000;      // text 131A16
    const ROUTE = 0xAAFF55;     // routeBand = brand B6F04A
    const ROUTE_EDGE = 0x55AA00; // routeEdge 4F8A10
    const S0 = 0x005500;        // mapGrades.s0 1F7A3A
    const S1 = 0x0055AA;        // mapGrades.s1 1F6FD1
    const S2 = 0xAA0000;        // mapGrades.s2 C62828
    const S3 = 0x000000;        // mapGrades.s3 131A16
    const UNGRADED = 0x555555;  // mapGrades.ungraded 6B756F
    const WARNING = 0xAA5500;   // mapLines.warning D9591A
    const BRANCH = 0x555555;    // Abzweigung wie ein Trail ohne Grad, ungraded 6B756F
    // Die Infofläche ist dunkel wie die Flächen der Folgeansicht (Design
    // 13, der dunkle Satz `AppColors.dark`).
    const FIELD = 0x000000;     // dark.ground 0E1411
    const TEXT_ON_FIELD = 0xFFFFFF; // dark.text F2F4EF
    const MUTED = 0xAAAAAA;     // dark.muted 9AA69D
    const MUTED_DARK = 0x555555; // dark.line 2A3630 ist auf MIP schwarz — eine Stufe heller, sonst unsichtbar
    const DS0 = 0x00AA55;       // grade dark.s0 4CC46E
    const DS1 = 0x55AAFF;       // grade dark.s1 5A9BF0
    const DS2 = 0xFF5555;       // grade dark.s2 F0605C
    const DS3 = 0xFFFFFF;       // grade dark.s3 F2F4EF

    //! Die Farbe eines S-Grads; -1 heißt ohne Grad.
    function grade(g as Number) as Number {
        if (g == 0) { return S0; }
        if (g == 1) { return S1; }
        if (g == 2) { return S2; }
        if (g == 3) { return S3; }
        return UNGRADED;
    }

    //! Dieselbe Stufe auf der dunklen Infofläche.
    function gradeOnDark(g as Number) as Number {
        if (g == 0) { return DS0; }
        if (g == 1) { return DS1; }
        if (g == 2) { return DS2; }
        if (g == 3) { return DS3; }
        return MUTED;
    }
}
