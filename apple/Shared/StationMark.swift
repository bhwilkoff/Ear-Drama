import SwiftUI

/// A station's label on the dial: its genre's board with the broadcast's year ticked. Given the station's name, the
/// label draws the name's monogram in its center (LabelSpec), so the dial says something where the web's read as a
/// blank disc: the web's dial passed no name (main thread's note, 2026-11-19).
struct StationMark: View {
    let station: Station
    var year: Int?
    let side: CGFloat

    var body: some View {
        LabelView(item: LabelItem(kind: .station, name: station.name, genre: station.genre, tickYear: year.map(String.init)),
                  side: side)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }
}
