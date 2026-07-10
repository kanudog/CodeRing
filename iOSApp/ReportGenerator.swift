// ReportGenerator.swift — the shareable code summary PDF.
// UIGraphicsPDFRenderer, US Letter, manual pagination. Every page carries the
// demo footer. Timeline rows paginate; long codes span pages cleanly.

import UIKit
import CodeCore

enum ReportGenerator {

    static func makePDF(for session: CodeSession) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter
        let margin: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeRing-Report-\(Int(session.startDate.timeIntervalSince1970)).pdf")

        func attr(_ text: String, _ size: CGFloat,
                  bold: Bool = false, color: UIColor = .black) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: bold ? UIFont.boldSystemFont(ofSize: size)
                            : UIFont.systemFont(ofSize: size),
                .foregroundColor: color
            ])
        }

        do {
            try renderer.writePDF(to: url) { ctx in
                var y: CGFloat = 0
                var page = 0

                func footer() {
                    attr("DEMO · NOT FOR CLINICAL USE — CodeRing", 9, bold: true,
                         color: .systemOrange)
                        .draw(at: CGPoint(x: margin, y: pageRect.height - 30))
                    attr("Page \(page)", 9, color: .darkGray)
                        .draw(at: CGPoint(x: pageRect.width - margin - 40,
                                          y: pageRect.height - 30))
                }

                func newPage() {
                    ctx.beginPage()
                    page += 1
                    y = margin
                    footer()
                }

                func ensure(_ needed: CGFloat) {
                    if y + needed > pageRect.height - 50 { newPage() }
                }

                func line(_ s: NSAttributedString, spacing: CGFloat = 4) {
                    ensure(s.size().height + spacing)
                    s.draw(at: CGPoint(x: margin, y: y))
                    y += s.size().height + spacing
                }

                newPage()

                // Title block
                line(attr("CodeRing — Code Summary", 22, bold: true))
                line(attr("DEMO REPORT — NOT FOR CLINICAL USE", 11, bold: true,
                          color: .systemOrange), spacing: 10)
                line(attr("\(session.protocolName) · \(df.string(from: session.startDate))"
                          + (session.deviceName.isEmpty ? "" : " · \(session.deviceName)"),
                          11, color: .darkGray), spacing: 14)

                // Patient
                let p = session.patient
                line(attr("Patient", 14, bold: true), spacing: 6)
                line(attr("Weight: \(p.weightLabel)  (\(p.sourceDetail))", 11))
                line(attr("Age: \(p.ageLabel)    Sex: \(p.sex.label)", 11), spacing: 14)

                // Summary stats
                let st = session.stats
                line(attr("Summary", 14, bold: true), spacing: 6)
                line(attr("Duration: \(crClock(st.totalSeconds))    "
                          + "CPR fraction: \(st.cprFractionPercent)    "
                          + "Pauses: \(st.pauseCount) (\(crClock(st.pausedSeconds)))", 11))
                line(attr("Epinephrine ×\(st.epiCount)    Shocks ×\(st.shockCount)    "
                          + "Rhythm checks ×\(st.rhythmCheckCount)", 11))

                var outcomes: [String] = []
                if let t = st.secondsToFirstEpi { outcomes.append("First epi \(crOffset(t))") }
                if let t = st.secondsToROSC { outcomes.append("ROSC \(crOffset(t))") }
                line(attr(outcomes.isEmpty ? "No ROSC recorded"
                                           : outcomes.joined(separator: "    "), 11),
                     spacing: 6)

                if !st.medEvents.isEmpty {
                    let meds = st.medEvents.sorted { $0.key < $1.key }
                        .map { "\($0.key) ×\($0.value)" }
                        .joined(separator: ", ")
                    line(attr("Medications: \(meds)", 11), spacing: 14)
                } else {
                    y += 8
                }

                // Timeline
                line(attr("Event Timeline", 14, bold: true), spacing: 8)
                for event in session.events {
                    ensure(18)
                    attr(event.stamp, 10, bold: true)
                        .draw(at: CGPoint(x: margin, y: y))
                    attr("[\(event.category.label)]", 10, color: .darkGray)
                        .draw(at: CGPoint(x: margin + 52, y: y))
                    let text = event.detail.map { "\(event.title) — \($0)" } ?? event.title
                    attr(text, 10)
                        .draw(in: CGRect(x: margin + 130, y: y,
                                         width: pageRect.width - margin * 2 - 130,
                                         height: 16))
                    y += 18
                }
            }
            return url
        } catch {
            return nil
        }
    }
}
