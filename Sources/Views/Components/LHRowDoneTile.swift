import SwiftUI

// MARK: - LHRow.DoneTile (standard §1.4a, 2.3 amendment 1)
//
// The one done marker for a browse row whose thing is done: a logged care item, a read lesson.
// The row's 36pt glyph tile becomes the `positive` check tile; the row's meta line says what was
// done ("Logged 1h · Oct 4", "Read"), never a score. The 22pt circle stays the To confirm control
// (§1.3) and never marks "done" anywhere else. [grep] `LHRow.DoneTile(` only inside an
// `LHRow.Browse` leading slot (standard_lint rule `done-tile-row`).

extension LHRow {
    struct DoneTile: View {
        var body: some View {
            LHRowGlyph(systemImage: "checkmark", tint: .positive)
        }
    }
}
