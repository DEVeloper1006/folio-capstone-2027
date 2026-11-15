import SwiftData
import Foundation

@Model
final class ClassSpace {
    var name: String
    var courseCode: String
    var instructorName: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \WorkedExample.classSpace)
    var workedExamples: [WorkedExample]

    init(name: String, courseCode: String, instructorName: String = "Dr. Mock") {
        self.name = name
        self.courseCode = courseCode
        self.instructorName = instructorName
        self.createdAt = Date()
        self.workedExamples = []
    }
}
