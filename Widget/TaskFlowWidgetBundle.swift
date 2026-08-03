import WidgetKit
import SwiftUI

/// The Widget extension entry point.
///
/// A `WidgetBundle` may expose multiple widgets; Task-Flow currently ships a
/// single one. Add further `Widget` values to `body` to grow the bundle.
@main
struct TaskFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
    }
}
