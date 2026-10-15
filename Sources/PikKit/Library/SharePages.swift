import Foundation

/// HTML que sirve el servidor de enlaces (visor de video/captura con transcripción).
enum SharePages {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let foxSVG = """
    <svg viewBox="0 0 100 100" width="28" height="28" aria-hidden="true">
      <path d="M50 33L35 29 16 3 6 43 2 58 50 97 98 58 94 43 84 3 65 29Z" fill="#FF7A1A" stroke="#FF7A1A" stroke-width="3" stroke-linejoin="round"/>
      <path d="M2 58Q27 68 50 56Q73 68 98 58L50 97Z" fill="#FFF5E6"/>
      <path d="M24 49Q34 43 43 52Q33 60 24 49ZM76 49Q66 43 57 52Q67 60 76 49Z" fill="#221733"/>
      <path d="M43 86Q50 83 57 86Q57 92 50 95Q43 92 43 86Z" fill="#221733"/>
    </svg>
    """

    private static let style = """
    :root{color-scheme:dark}
    *{box-sizing:border-box}
    body{margin:0;background:#14111f;color:#f4f1fa;font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
    header{display:flex;align-items:center;gap:10px;padding:14px 24px;border-bottom:1px solid #ffffff14}
    header b{font-size:17px;letter-spacing:.2px}
    main{max-width:1080px;margin:0 auto;padding:24px}
    h1{font-size:24px;margin:18px 0 4px}
    .meta{color:#a59fb8;font-size:13px;margin-bottom:16px}
    video,img.shot{width:100%;max-height:72vh;background:#000;border-radius:14px;display:block}
    img.shot{object-fit:contain}
    .card{background:#1f1b2e;border:1px solid #ffffff12;border-radius:14px;padding:16px 18px;margin-top:20px}
    .card h2{font-size:14px;margin:0 0 10px;text-transform:uppercase;letter-spacing:.8px;color:#ff9a4d}
    .seg{display:flex;gap:12px;padding:5px 6px;border-radius:8px;cursor:pointer}
    .seg:hover{background:#ffffff0d}
    .seg time{color:#ff9a4d;font-variant-numeric:tabular-nums;min-width:48px}
    a.btn{display:inline-block;margin-top:12px;background:#ff7a1a;color:#fff;text-decoration:none;padding:8px 14px;border-radius:999px;font-weight:600;font-size:13px}
    .center{min-height:70vh;display:grid;place-items:center;text-align:center}
    """

    static func page(title: String, body: String, script: String = "") -> String {
        """
        <!doctype html><html lang="es"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(escape(title)) · Pik</title><style>\(style)</style></head>
        <body><header>\(foxSVG)<b>Pik</b></header><main>\(body)</main>\(script)</body></html>
        """
    }

    static func landing() -> String {
        page(title: "Pik", body: """
        <div class="center"><div>\(foxSVG.replacingOccurrences(of: "28", with: "72"))
        <h1>Pik</h1><p class="meta">\(t("Screen recording that lives on your Mac.", "Grabaciones de pantalla que viven en tu Mac."))</p></div></div>
        """)
    }

    static func message(_ title: String, _ detail: String) -> String {
        page(title: title, body: """
        <div class="center"><div><h1>\(escape(title))</h1><p class="meta">\(escape(detail))</p></div></div>
        """)
    }

    static func viewer(_ item: LibraryEntry) -> String {
        let token = item.shareToken
        let media: String
        switch item.kind {
        case .screenshot:
            media = "<img class=\"shot\" src=\"/media/\(token)\" alt=\"\(escape(item.title))\">"
        default:
            let track = item.transcript.isEmpty ? "" : "<track kind=\"captions\" srclang=\"es\" label=\"\(t("Transcript", "Transcripción"))\" src=\"/vtt/\(token)\">"
            media = "<video id=\"v\" controls playsinline preload=\"metadata\" poster=\"/thumb/\(token)\" src=\"/media/\(token).mp4\">\(track)</video>"
        }
        var cards = ""
        if !item.transcript.isEmpty {
            let rows = item.transcript.map { seg in
                "<div class=\"seg\" data-t=\"\(seg.start)\"><time>\(Fmt.duration(seg.start))</time><span>\(escape(seg.text))</span></div>"
            }.joined()
            cards += "<div class=\"card\"><h2>\(t("Transcript", "Transcripción"))</h2>\(rows)</div>"
        }
        let meta = "\(Fmt.dateTime(item.createdAt))" + (item.duration > 0 ? " · \(Fmt.duration(item.duration))" : "")
        let download = "<a class=\"btn\" href=\"/media/\(token).\(item.fileURL?.pathExtension ?? "mp4")\" download>\(t("Download", "Descargar"))</a>"
        let script = """
        <script>document.querySelectorAll('.seg').forEach(function(e){e.onclick=function(){var v=document.getElementById('v');if(v){v.currentTime=parseFloat(e.dataset.t);v.play()}}})</script>
        """
        return page(title: item.title, body: """
        \(media)<h1>\(escape(item.title))</h1><div class="meta">\(escape(meta))</div>\(download)\(cards)
        """, script: script)
    }

    static func vtt(_ segments: [TranscriptSegment]) -> String {
        func ts(_ t: TimeInterval) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
        }
        var out = "WEBVTT\n\n"
        for s in segments {
            out += "\(ts(s.start)) --> \(ts(s.start + max(s.duration, 0.5)))\n\(s.text)\n\n"
        }
        return out
    }
}
