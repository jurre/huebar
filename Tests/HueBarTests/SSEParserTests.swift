import Foundation
import Testing
@testable import HueBar

@Suite("SSEParser")
struct SSEParserTests {
    private func makeEventJSON(id: String = "ev-1") -> String {
        """
        [{"creationtime":"2024-02-06T09:34:09Z","id":"\(id)","type":"update","data":[{"id":"light-1","type":"light","on":{"on":true}}]}]
        """
    }

    @Test("Parses a single complete event (id + data + blank line)")
    func singleCompleteEvent() {
        let parser = SSEParser()
        #expect(parser.processLine("id: 1707212049:0") == nil)
        #expect(parser.processLine("data: \(makeEventJSON())") == nil)

        let events = parser.processLine("")
        #expect(events != nil)
        #expect(events?.count == 1)
        #expect(events?[0].id == "ev-1")
        #expect(events?[0].type == .update)
        #expect(events?[0].data[0].on?.on == true)
    }

    @Test("Multi-line data lines are concatenated")
    func multiLineData() {
        let parser = SSEParser()
        // Split JSON across two data: lines — they get joined with \n
        let part1 = "[{\"creationtime\":\"2024-02-06T09:34:09Z\","
        let part2 = "\"id\":\"ev-1\",\"type\":\"update\",\"data\":[{\"id\":\"light-1\",\"type\":\"light\"}]}]"

        #expect(parser.processLine("data: \(part1)") == nil)
        #expect(parser.processLine("data: \(part2)") == nil)

        let events = parser.processLine("")
        #expect(events != nil)
        #expect(events?.count == 1)
        #expect(events?[0].id == "ev-1")
    }

    @Test("Comment lines (: prefix) are ignored")
    func commentLinesIgnored() {
        let parser = SSEParser()
        #expect(parser.processLine(": this is a comment") == nil)
        #expect(parser.processLine("data: \(makeEventJSON())") == nil)
        #expect(parser.processLine(": another comment") == nil)

        let events = parser.processLine("")
        #expect(events != nil)
        #expect(events?.count == 1)
    }

    @Test("Unknown fields (event:, retry:) are ignored")
    func unknownFieldsIgnored() {
        let parser = SSEParser()
        #expect(parser.processLine("event: message") == nil)
        #expect(parser.processLine("retry: 5000") == nil)
        #expect(parser.processLine("data: \(makeEventJSON())") == nil)

        let events = parser.processLine("")
        #expect(events != nil)
        #expect(events?.count == 1)
    }

    @Test("Parser resets after blank line — second event parses correctly")
    func secondEventAfterReset() {
        let parser = SSEParser()

        // First event
        _ = parser.processLine("data: \(makeEventJSON(id: "ev-1"))")
        let first = parser.processLine("")
        #expect(first?[0].id == "ev-1")

        // Second event
        _ = parser.processLine("id: 1707212050:0")
        _ = parser.processLine("data: \(makeEventJSON(id: "ev-2"))")
        let second = parser.processLine("")
        #expect(second?[0].id == "ev-2")
    }

    @Test("reset() clears the internal buffer")
    func resetClearsBuffer() {
        let parser = SSEParser()
        _ = parser.processLine("data: \(makeEventJSON())")

        parser.reset()

        // Blank line after reset should yield nil (buffer was cleared)
        let events = parser.processLine("")
        #expect(events == nil)
    }

    @Test("Malformed JSON in data lines returns nil, does not crash")
    func malformedJSON() {
        let parser = SSEParser()
        _ = parser.processLine("data: {not valid json!!!")
        let events = parser.processLine("")
        #expect(events == nil)
    }

    @Test("data: without trailing space (5-char prefix) is handled")
    func dataWithoutTrailingSpace() {
        let parser = SSEParser()
        // "data:" with no space after the colon
        _ = parser.processLine("data:\(makeEventJSON())")
        let events = parser.processLine("")
        #expect(events != nil)
        #expect(events?.count == 1)
        #expect(events?[0].id == "ev-1")
    }

    @Test("Carriage return as blank line delimiter triggers event dispatch")
    func carriageReturnDelimiter() {
        let parser = SSEParser()
        _ = parser.processLine("data: \(makeEventJSON())")
        let events = parser.processLine("\r")
        #expect(events != nil)
        #expect(events?.count == 1)
        #expect(events?[0].id == "ev-1")
    }

    @Test("Consecutive blank lines do not crash or produce duplicate events")
    func consecutiveBlankLines() {
        let parser = SSEParser()
        _ = parser.processLine("data: \(makeEventJSON())")

        let first = parser.processLine("")
        #expect(first != nil)
        #expect(first?.count == 1)

        // Subsequent blank lines with no new data should return nil
        #expect(parser.processLine("") == nil)
        #expect(parser.processLine("") == nil)
        #expect(parser.processLine("\r") == nil)
    }
}
