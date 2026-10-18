import Foundation
import Testing
@testable import AlexaAssist

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Test func commands() {
    let now = at(18, 9)
    #expect(CommandBuilder.timer(minutes: 10) == "set a timer for 10 minutes")
    #expect(CommandBuilder.timer(minutes: 1, label: " ") == "set a timer for 1 minute")
    #expect(CommandBuilder.timer(minutes: 25, label: "Focus") == "set a focus timer for 25 minutes")
    #expect(CommandBuilder.alarm(at: at(18, 6, 30), now: now, calendar: utc) == "set an alarm for 6:30 am")
    #expect(CommandBuilder.alarm(at: at(19, 7), now: now, calendar: utc) == "set an alarm for 7 am tomorrow")
    #expect(CommandBuilder.alarm(at: at(18, 0, 5), now: now, calendar: utc) == "set an alarm for 12:05 am")
    #expect(CommandBuilder.alarm(at: at(21, 18), now: now, calendar: utc) == "set an alarm for 6 pm on wednesday")
    #expect(CommandBuilder.alarm(at: at(30, 12), now: now, calendar: utc) == "set an alarm for 12 pm on october 30")
}

@Test func reminderPayload() throws {
    let device = EchoDevice(id: "G1", name: "Dot", deviceType: "A4ZXE0RM7LQ7A", isOnline: true)
    let when = Date(timeIntervalSince1970: 1_792_350_000)
    let p = CloudBackend.reminderPayload("call mom", at: when, on: device, now: when - 3600)
    let local = DateFormatter()
    local.dateFormat = "yyyy-MM-dd HH:mm:ss"
    #expect(p["type"] as? String == "Reminder")
    #expect(p["reminderLabel"] as? String == "call mom")
    #expect(p["alarmTime"] as? Int == 1_792_350_000_000)
    #expect(p["deviceSerialNumber"] as? String == "G1" && p["deviceType"] as? String == "A4ZXE0RM7LQ7A")
    #expect("\(p["originalDate"]!) \((p["originalTime"] as! String).prefix(8))" == local.string(from: when))
    #expect(p["status"] as? String == "ON")
    _ = try JSONSerialization.data(withJSONObject: p)  // must serialize
}

@Test func notificationMapping() throws {
    let now = Date(timeIntervalSince1970: 1_792_300_000)
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    let tomorrow = f.string(from: now + 86400)
    let json = """
    {"notifications":[
      {"id":"A#1","type":"Alarm","status":"ON","deviceSerialNumber":"S1","originalDate":"\(tomorrow)","originalTime":"06:30:00.000","alarmLabel":""},
      {"id":"A#2","type":"MusicAlarm","status":"ON","deviceSerialNumber":"S1","originalDate":"2020-01-01","originalTime":"07:00:00.000"},
      {"id":"A#3","type":"Alarm","status":"ON","deviceSerialNumber":"S1","originalDate":"2020-01-01","originalTime":"07:00:00.000","recurringPattern":"P1D"},
      {"id":"T#1","type":"Timer","status":"ON","deviceSerialNumber":"S1","triggerTime":\((now.timeIntervalSince1970 + 60) * 1000),"timerLabel":"tea"},
      {"id":"T#2","type":"Timer","status":"PAUSED","deviceSerialNumber":"S1","remainingTime":5000},
      {"id":"R#1","type":"Reminder","status":"ON","deviceSerialNumber":"S1","alarmTime":\((now.timeIntervalSince1970 + 3600) * 1000),"reminderLabel":"call mom"},
      {"id":"X#1","type":"Something","status":"ON","deviceSerialNumber":"S1"}
    ]}
    """
    let alerts = try JSONDecoder().decode(NotificationsDTO.self, from: Data(json.utf8)).alerts(now: now)
    #expect(Set(alerts.map(\.id)) == ["T#1", "R#1", "A#1", "A#3"])  // A#2 already fired, T#2 paused
    #expect(alerts.first?.id == "T#1")
    #expect(alerts.first?.fireDate == now + 60)
    #expect(alerts.first?.label == "tea")
    #expect(alerts.first { $0.id == "A#1" }?.label == nil)
    #expect(alerts.first { $0.id == "A#3" }?.repeats == true)
}

@Test func devices() throws {
    let json = """
    {"devices":[
      {"serialNumber":"G1","accountName":"Bedroom Echo Dot","deviceType":"A4ZXE0RM7LQ7A","online":true,"capabilities":["MICROPHONE","TIMERS_AND_ALARMS"]},
      {"serialNumber":"P1","accountName":"This iPhone","deviceType":"A2IVLV5VM2W81","online":true,"capabilities":["MICROPHONE"]}
    ]}
    """
    let echos = try JSONDecoder().decode(DevicesDTO.self, from: Data(json.utf8)).devices!.compactMap(\.echoDevice)
    #expect(echos.map(\.name) == ["Bedroom Echo Dot"])
}

@Test func signInRequest() throws {
    let r = SignInRequest()
    let items = URLComponents(url: r.url, resolvingAgainstBaseURL: false)!.queryItems!
    let clientID = items.first { $0.name == "openid.oa2.client_id" }!.value!
    #expect(r.url.host == "www.amazon.com")
    #expect(clientID.hasPrefix("device:") && clientID.hasSuffix("23413249564c5635564d32573831"))  // hex("#A2IVLV5VM2W81")
    #expect(clientID.count == "device:".count + 64 + 28)
    #expect(r.authorizationCode(from: URL(string: "https://www.amazon.com/ap/maplanding?openid.oa2.authorization_code=abc")!) == "abc")
    #expect(r.authorizationCode(from: URL(string: "https://www.amazon.com/ap/signin")!) == nil)
}
