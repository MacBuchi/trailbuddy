// ERZEUGT von tool/watch_layout.py aus tool/watch_layout.json (symbols) — nie von Hand (#558).
import Toybox.Graphics;
import Toybox.Lang;

//! Die Zeichen der Uhr, 16 px hoch, aus Fläche, Kreis, Linie und Vieleck.
//! Je Befehl: Art (p Vieleck, r Rechteck, c Kreis, o Ring, l Linie), Farbe
//! (m die gereichte, r Lime), dann die Zahlen je ein Zeichen, Wert + „0“.
module TbSym {
    //! Breite des Zeichens [id].
    function width(id as Number) as Number {
        return id == 11 || id == 12 ? 22 : 16;
    }

    function code(id as Number) as String {
        if (id == 0) {  // stopwatch
            return "rm6042om8952lm89852";
        } else if (id == 1) {  // clock
            return "om8862lm84882lm88;82";
        } else if (id == 2) {  // distance
            return "rm032:rm>32:rm37:2pm328656;pm3>8:5:;";
        } else if (id == 3) {  // heart
            return "cm554cm;54pm316?68?";
        } else if (id == 4) {  // peaks
            return "pm51>6398;5?>";
        } else if (id == 5) {  // signpost
            return "rm712>pm523;3>5;828";
        } else if (id == 6) {  // flag
            return "rm312>pm552>2;5>959";
        } else if (id == 7) {  // angle
            return "lm2>>>2lm2>;32lm:>9;1lm9;781";
        } else if (id == 8) {  // play
            return "pr342>84>";
        } else if (id == 9) {  // pause
            return "rm324<rm924<";
        } else if (id == 10) {  // plane
            return "pm51:3<>5?3=2pm4873262;5pm43:163659lr1???2";
        } else if (id == 11) {  // wheelie
            return "lr0?F?2om5;32om@532lm5;751lm75=21lm75;91lm;95;1lm;9=21lm=2@51";
        } else if (id == 12) {  // stoppie
            return "lr0?F?2omA;32om6532lm65:31lm:3?51lm:3;91lm;9651lm;9?51lm?5A;1";
        }
        return "";
    }

    function v(s as Array<Char>, i as Number) as Number {
        return s[i].toNumber() - 48;
    }

    //! Zeichnet [id] mit der linken oberen Ecke bei [x], [y]; [c] ist die
    //! Farbe der Teile „m“, Lime bleibt Lime.
    function draw(dc as Dc, id as Number, x as Number, y as Number, c as Number) as Void {
        var s = code(id).toCharArray();
        var n = s.size();
        var i = 0;
        while (i < n) {
            var k = s[i];
            dc.setColor(s[i + 1] == 'm' ? c : TbColors.ROUTE, Graphics.COLOR_TRANSPARENT);
            i += 2;
            if (k == 'p') {
                var pts = [] as Array<[Numeric, Numeric]>;
                var cnt = v(s, i);
                i++;
                for (var j = 0; j < cnt; j++) {
                    pts.add([x + v(s, i), y + v(s, i + 1)]);
                    i += 2;
                }
                dc.fillPolygon(pts);
            } else if (k == 'r') {
                dc.fillRectangle(x + v(s, i), y + v(s, i + 1), v(s, i + 2), v(s, i + 3));
                i += 4;
            } else if (k == 'c') {
                dc.fillCircle(x + v(s, i), y + v(s, i + 1), v(s, i + 2));
                i += 3;
            } else if (k == 'o') {
                dc.setPenWidth(v(s, i + 3));
                dc.drawCircle(x + v(s, i), y + v(s, i + 1), v(s, i + 2));
                i += 4;
            } else {
                dc.setPenWidth(v(s, i + 4));
                dc.drawLine(x + v(s, i), y + v(s, i + 1), x + v(s, i + 2), y + v(s, i + 3));
                i += 5;
            }
        }
        dc.setPenWidth(1);
    }
}
