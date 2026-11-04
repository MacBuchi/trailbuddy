import Toybox.Lang;
import Toybox.Math;

//! Der Ring außen herum (Entwurf „Ring und Seiten", Betreiber 2026-11-04:
//! Variante A): Ein Umlauf ist die ganze Route, im Uhrzeigersinn, Start
//! und Ziel oben an einer kleinen Lücke. Gefahren Lime, voraus Grau,
//! Trails in der Farbe ihres S-Grads (dunkler Satz, der Ring liegt auf
//! Schwarz), eine weiße Marke für die eigene Position.
module TbRing {
    //! Radius der Ringmitte, Strichbreite, und der schwarze Rand darunter
    //! (Karte innen bis MAP_R).
    const RING_R = 114;
    const RING_W = 8;
    const MAP_R = 107;
    //! Die Lücke oben in Grad (Start = Ziel).
    const GAP_DEG = 4;

    //! Anteil der Route → Winkel für `Dc.drawArc` (0° = 3 Uhr, gegen den
    //! Uhrzeigersinn positiv): 0 liegt rechts neben der Lücke, 1 links.
    function deg(f as Float) as Number {
        if (f < 0.0) { f = 0.0; }
        if (f > 1.0) { f = 1.0; }
        return Math.round(90 - GAP_DEG / 2 - f * (360 - GAP_DEG)).toNumber();
    }

    //! Ein Anteil der Route aus Metern; 0, wenn die Route keine Länge hat.
    function share(m as Float, lengthM as Float) as Float {
        if (lengthM <= 0.0) { return 0.0; }
        var f = m / lengthM;
        return f < 0.0 ? 0.0 : (f > 1.0 ? 1.0 : f);
    }
}
