import XCTest
@testable import HealthCore

final class ExamDetectorTests: XCTestCase {
    func testFindsExams() {
        for title in ["STAT 400 Midterm", "Final exam – BIO 110", "Quiz 3", "Chem quizzes", "ECON test", "MIDTERM 2"] {
            XCTAssertTrue(ExamDetector.isExam(title), title)
        }
    }

    func testSkipsEventsAboutExams() {
        for title in ["Midterm review session", "Final exam prep", "Study group for quiz", "Office hours before the final",
                      "Practice exam", "Covid test", "Finally free", "Testing center tour", "Lunch"] {
            XCTAssertFalse(ExamDetector.isExam(title), title)
        }
    }

    func testKind() {
        XCTAssertEqual(ExamDetector.kind(of: "Final exam – BIO 110"), "Final")
        XCTAssertEqual(ExamDetector.kind(of: "STAT 400 Midterm"), "Midterm")
        XCTAssertEqual(ExamDetector.kind(of: "Quiz 3"), "Quiz")
        XCTAssertEqual(ExamDetector.kind(of: "ECON test"), "Test")
        XCTAssertEqual(ExamDetector.kind(of: "Organic chem exam"), "Exam")
    }
}
