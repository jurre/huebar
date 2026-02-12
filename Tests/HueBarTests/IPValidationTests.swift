import Testing
@testable import HueBar

struct IPValidationTests {
    @Test func validIPv4() {
        #expect(IPValidation.isValid("192.168.1.1"))
        #expect(IPValidation.isValid("10.0.0.1"))
        #expect(IPValidation.isValid("255.255.255.255"))
        #expect(IPValidation.isValid("0.0.0.0"))
    }

    @Test func validIPv6() {
        #expect(IPValidation.isValid("::1"))
        #expect(IPValidation.isValid("fe80::1"))
        #expect(IPValidation.isValid("2001:db8::1"))
    }

    @Test func rejectsHostnames() {
        #expect(!IPValidation.isValid("evil.com"))
        #expect(!IPValidation.isValid("evil.com/steal?x="))
        #expect(!IPValidation.isValid("bridge.local"))
    }

    @Test func rejectsEmptyAndWhitespace() {
        #expect(!IPValidation.isValid(""))
        #expect(!IPValidation.isValid("   "))
    }

    @Test func rejectsPathInjection() {
        #expect(!IPValidation.isValid("192.168.1.1/evil"))
        #expect(!IPValidation.isValid("192.168.1.1:8080/path"))
        #expect(!IPValidation.isValid("192.168.1.1:8080"))
    }

    @Test func rejectsURLSchemes() {
        #expect(!IPValidation.isValid("https://192.168.1.1"))
        #expect(!IPValidation.isValid("http://evil.com"))
    }
}
