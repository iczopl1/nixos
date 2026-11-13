// Silnik cząsteczkowy – rysuje na Canvas. Max 80 cząsteczek, 30 FPS.
// Każdy motyw ma własny spawner i fizykę.
import QtQuick

Canvas {
    id: canvas
    required property string theme
    required property bool running

    property var particles: []
    property int maxParticles: 80

    // Motyw "cursor" – pozycja kursora na TYM ekranie (Particles.qml, polling mmsg)
    property bool cursorActive: false
    property real cursorX: 0
    property real cursorY: 0

    // Seed dla pseudo-losowości
    function rand(min, max) { return min + Math.random() * (max - min) }
    function randInt(min, max) { return Math.floor(rand(min, max + 1)) }

    // --- Spawner: tworzy nową cząsteczkę wg motywu ---
    function spawn() {
        var p = {}
        p.x = rand(0, width)
        p.life = 1.0  // 1.0 = pełne życie, 0 = martwe

        if (theme === "leaves") {
            p.y = rand(-20, -5)
            p.vx = rand(-0.6, 0.6)
            p.vy = rand(2, 4)        // szybszy spadek – więcej ruchu, łatwiej zauważyć
            p.rot = rand(0, 360)
            p.vrot = rand(-3, 3)
            p.size = rand(24, 54)
            p.decay = rand(0.002, 0.004)
            p.color = ["#c0a060","#d4833a","#b85c1a","#8b4513","#e8a830"][randInt(0,4)]
            p.swing = rand(0.3, 1.0)
            p.swingT = rand(0, Math.PI * 2)

        } else if (theme === "rain") {
            p.y = rand(-20, 0)
            p.vx = rand(-0.3, 0.3)
            p.vy = rand(8, 14)
            p.length = rand(30, 60)  // 3x (było 10-20)
            p.decay = rand(0.004, 0.008)
            p.color = "#6ab0d4"
            p.alpha = rand(0.3, 0.7)

        } else if (theme === "snow") {
            p.y = rand(-10, 0)
            p.vx = rand(-0.5, 0.5)
            p.vy = rand(1.5, 3)      // szybszy spadek – więcej ruchu, łatwiej zauważyć
            p.size = rand(6, 21)
            p.decay = rand(0.002, 0.005)
            p.color = "#ddeeff"
            p.swing = rand(0.2, 0.8)
            p.swingT = rand(0, Math.PI * 2)

        } else if (theme === "sparks") {
            p.x = rand(width * 0.2, width * 0.8)
            p.y = height + rand(0, 20)
            p.vx = rand(-2.5, 2.5)
            p.vy = rand(-6, -2)
            p.size = rand(6, 15)  // 3x (było 2-5)
            p.decay = rand(0.01, 0.025)
            p.color = ["#ff9900","#ffcc00","#ff6600","#ffffff"][randInt(0,3)]
            p.gravity = 0.07

        } else if (theme === "cursor") {
            p.x = cursorX + rand(-4, 4)
            p.y = cursorY + rand(-4, 4)
            p.vx = rand(-0.4, 0.4)
            p.vy = rand(-0.8, -0.2)  // leciutko w górę, jak iskierki z kursora
            p.size = rand(20, 60)    // 10x (było 2-6)
            p.decay = rand(0.03, 0.06)  // szybko gasną – ślad, nie smuga na cały ekran
            p.color = ["#9eeaf9","#e0af68","#f7768e","#c0caf5"][randInt(0,3)]
        }
        return p
    }

    // --- Update cząsteczki o jeden krok ---
    function step(p) {
        if (theme === "leaves") {
            p.swingT += 0.04
            p.x  += p.vx + Math.sin(p.swingT) * p.swing
            p.y  += p.vy
            p.rot += p.vrot
            p.life -= p.decay
            if (p.y > height + 60) p.life = 0  // margines ≥ max rozmiaru listka (54, 3x)

        } else if (theme === "rain") {
            p.x += p.vx; p.y += p.vy
            p.life -= p.decay
            if (p.y > height + 65) p.life = 0  // margines ≥ max długości smugi (60, 3x)

        } else if (theme === "snow") {
            p.swingT += 0.02
            p.x += p.vx + Math.sin(p.swingT) * p.swing
            p.y += p.vy
            p.life -= p.decay
            if (p.y > height + 10) p.life = 0

        } else if (theme === "sparks") {
            p.vy += p.gravity
            p.x  += p.vx; p.y += p.vy
            p.life -= p.decay

        } else if (theme === "cursor") {
            p.x += p.vx; p.y += p.vy
            p.life -= p.decay
        }
        return p
    }

    // --- Rysuj pojedynczą cząsteczkę ---
    function draw(ctx, p) {
        ctx.globalAlpha = Math.max(0, p.life)

        if (theme === "leaves") {
            // ctx.ellipse() nie jest wspierane przez Canvas2D w Qt/Quickshell – rysowało się
            // "po cichu" nic (QML Canvas gubi wyjątki JS w onPaint bez żadnego logu/błędu).
            // Zastąpione uniwersalnym arc() + scale() – ten sam spłaszczony kształt listka.
            // Czarny obrys: widoczne na KAŻDYM tle, nie tylko na kontrastowym.
            ctx.save()
            ctx.translate(p.x, p.y)
            ctx.rotate(p.rot * Math.PI / 180)
            ctx.scale(1, 0.6)
            ctx.beginPath()
            ctx.arc(0, 0, p.size / 2, 0, Math.PI * 2)
            ctx.fillStyle = p.color
            ctx.fill()
            ctx.lineWidth = 3 / 0.6  // kompensacja ctx.scale(1,0.6) na obrysie
            ctx.strokeStyle = "#1a1a1aee"
            ctx.stroke()
            ctx.restore()

        } else if (theme === "rain") {
            ctx.strokeStyle = p.color
            ctx.globalAlpha = Math.max(0, p.life) * Math.max(p.alpha, 0.6)  // podniesiona widoczność
            ctx.lineWidth = 3  // 3x (było 1)
            ctx.beginPath()
            ctx.moveTo(p.x, p.y)
            ctx.lineTo(p.x + p.vx * 2, p.y - p.length)
            ctx.stroke()

        } else if (theme === "snow") {
            // niebieskawy obrys: biały płatek na jasnej/białej tapecie był praktycznie niewidoczny
            ctx.beginPath()
            ctx.arc(p.x, p.y, p.size / 2, 0, Math.PI * 2)
            ctx.fillStyle = p.color
            ctx.fill()
            ctx.lineWidth = 2
            ctx.strokeStyle = "#5a7a99"
            ctx.stroke()

        } else if (theme === "sparks") {
            ctx.fillStyle = p.color
            var s = p.size * p.life
            ctx.beginPath()
            ctx.arc(p.x, p.y, Math.max(0.5, s / 2), 0, Math.PI * 2)
            ctx.fill()

        } else if (theme === "cursor") {
            // dosłowne "piksele" – kwadraty, nie kółka
            ctx.fillStyle = p.color
            ctx.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size)
        }

        ctx.globalAlpha = 1.0
    }

    // --- Pętla animacji ---
    Timer {
        id: loop
        interval: 33  // ~30 FPS
        repeat: true
        running: canvas.running && canvas.width > 0

        // Spawnuj nowe cząsteczki
        property int spawnAccum: 0
        onTriggered: {
            if (!canvas.running) { canvas.particles = []; canvas.requestPaint(); return }

            // Usuń martwe
            canvas.particles = canvas.particles.filter(p => p.life > 0)

            // Spawn rate wg motywu
            var spawnRate = {
                leaves: 1.2, rain: 2.5, snow: 2.0, sparks: 1.5,
                cursor: canvas.cursorActive ? 4 : 0  // piksele tylko na ekranie z kursorem
            }
            var rate = spawnRate[canvas.theme] || 0
            var capForTheme = (canvas.theme === "cursor") ? 10 : canvas.maxParticles
            spawnAccum += rate
            while (spawnAccum >= 1 && canvas.particles.length < capForTheme) {
                canvas.particles.push(canvas.spawn())
                spawnAccum -= 1
            }
            if (spawnAccum >= 1) spawnAccum = 0

            // Update fizyki
            canvas.particles = canvas.particles.map(p => canvas.step(p))

            canvas.requestPaint()
        }
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        for (var i = 0; i < particles.length; i++) {
            draw(ctx, particles[i])
        }
    }

    // Wyczyść gdy motyw wyłączony
    onRunningChanged: {
        if (!running) { particles = []; requestPaint() }
    }
}
