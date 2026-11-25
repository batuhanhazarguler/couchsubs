// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

final class GamePhoneTextTests: XCTestCase {
    private func line(_ text: String, _ y: Double, _ left: Double = 0.2, _ right: Double = 0.8) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: y, right: right, bottom: y + 0.031))
    }

    func testCaptionsRemainTranslatableButStandaloneTagsAndUserNamesStayInTheGame() {
        let reading = Reading(lines: [line("@vice.305", 0.63), line("Meet me #NightRide", 0.68),
                                      line("#sunset #leonida", 0.73), line("Tell @vice.305 to wait.", 0.80)])
        let kept = GamePhoneText.forTranslation(reading)
        XCTAssertEqual(GamePhoneText.groups(kept).flatMap(\.paragraphs), ["Meet me #NightRide", "Tell @vice.305 to wait."])
        let source = "Send the photo to @KaterinaDiva."
        XCTAssertEqual(GamePhoneText.keepIdentifiers(source, translation: "Fotoğrafı @katerinadiva'ya gönder."),
                       "Fotoğrafı @KaterinaDiva'ya gönder.")
        XCTAssertNil(GamePhoneText.keepIdentifiers(source, translation: "Fotoğrafı ona gönder."))
        XCTAssertNil(GamePhoneText.keepIdentifiers(source, translation: "Fotoğrafı @Joey'e gönder."))
    }

    func testEnglishShorthandAndNumericOcrCorrectionRespectNamesAndCodes() {
        let text = "We're in this 2gether. I left it 4u."
        XCTAssertEqual(GamePhoneText.englishModelInput(text), "We're in this together. I left it for you.")
        XCTAssertEqual(GamePhoneText.groups(Reading(lines: [line(text, 0.5)])).flatMap(\.paragraphs), [text])
        let codes = "Use B4, @4u, #2gether or gate C4."
        XCTAssertEqual(GamePhoneText.englishModelInput(codes), codes)
        XCTAssertEqual(GamePhoneText.englishModelInput("IO min out."), "10 min out.")
        XCTAssertEqual(GamePhoneText.englishModelInput("IO port. I owe him."), "IO port. I owe him.")
    }

    func testContactsAreMarkedOnlyInRecognizableMessageListAndCutWordsAreNeverCompleted() {
        let rows = [line("Suggestions", 0.04), line("Chase", 0.12), line("call me after ...", 0.16),
                    line("May", 0.25), line("Don't leave yet.", 0.29), line("Messages", 0.42),
                    line("Rose", 0.54), line("Meet me at 06:40.", 0.58)]
        let kept = GamePhoneText.forTranslation(Reading(lines: rows))
        XCTAssertEqual(kept.lines.map(\.text), ["Suggestions", "Chase", "call me after...", "May", "Don't leave yet.", "Messages",
                                                "Rose", "Meet me at 06:40."])
        XCTAssertEqual(kept.lines.map(\.listRole), [.heading, .contact, .preview, .contact, .preview, .heading, .contact, .preview])
        // Tek başlık da yeter: sallanan telefonda biri bir okumada kaçabilir.
        XCTAssertEqual(GamePhoneText.forTranslation(Reading(lines: Array(rows.dropFirst()))).lines.map(\.listRole),
                       [.contact, .preview, .contact, .preview, .heading, .contact, .preview])
        // Başlıksız ve kesik önizlemesiz üç ad-yanıt çifti liste sayılmaz.
        let plain = rows.filter { GamePhoneText.section($0.text) == nil && !$0.text.hasSuffix("...") }
        XCTAssertTrue(GamePhoneText.forTranslation(Reading(lines: plain)).lines.allSatisfy { $0.listRole == nil })
    }

    /// Başlığın simgesi yazı tanımada tek harf ya da işaret olarak okunur ("g Suggested"): artık atılır, satır yine
    /// başlıktır. Başlık içeren gerçek cümle başlık değildir.
    func testHeadingIconResidueIsDropped() {
        for text in ["g Suggested", "✱ Suggested", "Suggested", "Messages ☆", "• Messages", "O Messages"] {
            XCTAssertNotNil(GamePhoneText.section(text), text)
        }
        for text in ["Suggested items", "My Messages", "Messages from Joey", "Send Messages now"] {
            XCTAssertNil(GamePhoneText.section(text), text)
        }
    }

    /// LG, beta.93: GTA 6 Mesajlar ekranı (fotoğraftaki sıra). Telefon sallanırken her okuma başka: başlığın simgesi bir
    /// "g" okunur, bir okunmaz; "Messages" bir okumada kaçar; kutular birkaç piksel oynar. Liste her okumada liste, satırlar
    /// aynı sırada ve aynı rolde kalır; kişi adları ayrı satırdır.
    func testSwayingMessageListKeepsItsRolesInEveryRead() {
        func rows(_ dy: Double, suggested: String?, messages: Bool) -> Reading {
            func flat(_ text: String, _ y: Double, _ left: Double, _ right: Double = 0.95) -> TextLine {
                let box = TextBox(left: left + dy / 2, top: y + dy, right: right + dy / 2, bottom: y + dy + 0.031)
                var row = TextLine(text, box: box)
                row.phoneBox = box
                return row
            }
            var lines: [TextLine] = []
            if let suggested { lines.append(flat(suggested, 0.04, 0.05, 0.40)) }
            lines += [flat("Cal", 0.10, 0.30, 0.38), flat("$ in your mailbox. You bailed", 0.14, 0.30),
                      flat("Brian", 0.22, 0.30, 0.42), flat("Ok. There's some cash in t...", 0.26, 0.30)]
            if messages { lines.append(flat("Messages", 0.33, 0.03, 0.30)) }
            lines += [flat("Donnie", 0.40, 0.30, 0.45),
                      flat("Joey", 0.50, 0.30, 0.40), flat("Hey this is Joey from Coa...", 0.54, 0.30),
                      flat("Lucia (Yolanda phone)", 0.62, 0.30, 0.70), flat("Outside living better than ...", 0.66, 0.30),
                      flat("Shirley", 0.74, 0.30, 0.45), flat("Oh that's nice hon. aren't ...", 0.78, 0.30),
                      flat("Rusty Anchor", 0.88, 0.30, 0.62)]
            return Reading(lines: lines)
        }
        let expected: [(String, ScreenPhoneCard.Role)] = [
            ("Suggested", .heading), ("Cal", .contact), ("$ in your mailbox. You bailed", .preview), ("Brian", .contact),
            ("Ok. There's some cash in t...", .preview), ("Messages", .heading), ("Donnie", .contact), ("Joey", .contact),
            ("Hey this is Joey from Coa...", .preview), ("Lucia (Yolanda phone)", .contact),
            ("Outside living better than...", .preview), ("Shirley", .contact), ("Oh that's nice hon. aren't...", .preview),
            ("Rusty Anchor", .contact)]
        for (index, (suggested, messages)) in [("Suggested", true), ("g Suggested", true), ("✱ Suggested", false),
                                                (nil, true), (nil, false)].enumerated() {
            let groups = GamePhoneText.groups(GamePhoneText.forTranslation(rows(0.002 * Double(index), suggested: suggested,
                                                                                    messages: messages)))
            let wanted = expected.filter { (suggested != nil || $0.0 != "Suggested") && (messages || $0.0 != "Messages") }
            XCTAssertEqual(groups.map { $0.paragraphs.joined() }, wanted.map(\.0), "\(index)")
            XCTAssertEqual(groups.map { $0.phone?.role }, wanted.map(\.1), "\(index)")
        }
    }

    /// Kesik önizleme kesik çevrilir: yarım son sözcük ve sarkan edat çeviriye gitmez, çeviri "..." ile biter.
    func testCutPreviewIsTranslatedWithoutTheBrokenWord() {
        XCTAssertEqual(GamePhoneText.cutInput("Hey this is Joey from Coa..."), "Hey this is Joey")
        XCTAssertEqual(GamePhoneText.cutInput("Ok. There's some cash in t..."), "Ok. There's some cash")
        XCTAssertEqual(GamePhoneText.cutInput("Outside living better than..."), "Outside living better")
        XCTAssertEqual(GamePhoneText.cutInput("Oh that's nice hon. aren't..."), "Oh that's nice hon.")
        XCTAssertEqual(GamePhoneText.cutInput("Call me, then…"), "Call me")
        XCTAssertNil(GamePhoneText.cutInput("Meet me at 6."))
        XCTAssertNil(GamePhoneText.cutInput("Coa..."))
        XCTAssertEqual(GamePhoneText.cutTranslation("Selam, ben Joey."), "Selam, ben Joey...")
        XCTAssertEqual(GamePhoneText.cutTranslation("Dışarıda yaşamak daha iyi"), "Dışarıda yaşamak daha iyi...")
    }

    /// Sinan Bey (beta.100, 3399): "…" koymadan satır sonunda kesilen önizleme ("$ in your mailbox. You bailed") bağlamsız
    /// çevrilip uyduruluyordu ("Posta kutunda. Beni aradın"; "$" düşmüş). Sohbette tam çevirisi bilinen mesajın önizlemesi o
    /// çevirinin başı + "..."; bilinmiyorsa kesik metin "..." ipucuyla gider, sonu tamamlanmaz; baştaki "$" düşmez.
    func testClippedPreviewUsesTheKnownChatTranslationOrStaysCut() {
        XCTAssertEqual(GamePhoneText.clippedInput("$ in your mailbox. You bailed"), "$ in your mailbox. You bailed")
        XCTAssertEqual(GamePhoneText.clippedInput("Meet me at the"), "Meet me")
        XCTAssertNil(GamePhoneText.clippedInput("See you there."))
        XCTAssertNil(GamePhoneText.clippedInput("Okay"))
        XCTAssertEqual(GamePhoneText.cutHint("Meet me"), "Meet me...")
        XCTAssertEqual(GamePhoneText.keepingLeadingSymbol("$ in your mailbox", "Posta kutunda"), "$ Posta kutunda")
        XCTAssertEqual(GamePhoneText.keepingLeadingSymbol("$ in your mailbox", "$ posta kutunda"), "$ posta kutunda")
        XCTAssertEqual(GamePhoneText.keepingLeadingSymbol("in your mailbox", "Posta kutunda"), "Posta kutunda")
        let known = ["$ in your mailbox. You bailed me out again bro! You got away right? Tell me you got away. LMK!":
                        "$ posta kutunda. Beni yine kurtardın, kanka! Kaçtın, değil mi? Kaçtığını söyle bana. Haber ver!",
                     "I'm good. Thanks for the cash.": "İyiyim. Para için sağ ol."]
        let preview = try! XCTUnwrap(GamePhoneText.knownPreview("$ in your mailbox. You bailed", in: known))
        XCTAssertTrue(preview.hasPrefix("$ posta kutunda."), preview)
        XCTAssertTrue(preview.hasSuffix("..."), preview)
        XCTAssertLessThan(preview.count, 50)
        XCTAssertEqual(GamePhoneText.knownPreview("$ in your mailbox. You bailed", in: known), preview, "her seferinde aynı")
        // "…" ile kesik önizlemenin yarım sözcüğü eşleşmeye girmez.
        XCTAssertNotNil(GamePhoneText.knownPreview("$ in your mailbox. You bai...", in: known))
        XCTAssertNil(GamePhoneText.knownPreview("Hey this is Joey from Coa...", in: known), "bilinmeyen mesaj uydurulmaz")
        XCTAssertNil(GamePhoneText.knownPreview("I'm good", in: known), "çok kısa önizleme eşleşmez")
        // Para simgesi kumanda simgesi değildir; telefon yolunda tek başına "$" okuma çöpü sayılmaz.
        XCTAssertFalse(ButtonIcons.isIconToken("$"))
        XCTAssertEqual(OcrNoise.clean("$ in your mailbox", keepIdentifiers: true), "$ in your mailbox")
    }

    /// Ana ekran bileşeni (Sinan Bey, beta.100 3397): başlık ve sayaç tek grup, iki parça ("Reminders", "6 Notifications");
    /// rolü `widget`. Tek satır okunan "Reminders 6 Notifications" de ikiye ayrılır. Uygulama adı ("WhatUp") çevrilmez.
    func testHomeWidgetIsOneGroupWithTitleAndCounter() {
        func flat(_ text: String, _ left: Double, _ top: Double, _ right: Double) -> TextLine {
            var line = TextLine(text, box: TextBox(left: left, top: top, right: right, bottom: top + 0.028))
            line.phoneBox = line.box
            return line
        }
        let lines = [flat("Reminders", 0.16, 0.12, 0.45), flat("6 Notifications", 0.05, 0.155, 0.5), flat("WhatUp", 0.38, 0.86, 0.62)]
        let groups = GamePhoneText.groups(Reading(lines: lines))
        XCTAssertEqual(groups.map(\.paragraphs), [["Reminders", "6 Notifications"]])
        XCTAssertEqual(groups.first?.phone?.role, .widget)
        XCTAssertEqual(GamePhoneText.widgetParts("Reminders 6 Notifications")?.counter, "6 Notifications")
        XCTAssertNil(GamePhoneText.widgetParts("Call me 6 times"))
    }

    func testOpposingRepliesAndWrappedMessagesUseFlatDisplayCoordinates() {
        let rows = [line("Find someone who", 0.30, 0.10, 0.69), line("knows this road.", 0.334, 0.10, 0.64),
                    line("on my way", 0.372, 0.38, 0.93)]
        XCTAssertEqual(GamePhoneText.groups(Reading(lines: rows)).flatMap(\.paragraphs), ["Find someone who knows this road.", "on my way"])
        func tilted(_ text: String, _ x: Double, _ y: Double, _ right: Double) -> TextLine {
            var row = TextLine(text, box: TextBox(left: x, top: y, right: right, bottom: y + 0.068))
            row.phoneBox = TextBox(left: x, top: y, right: right, bottom: y + 0.026)
            return row
        }
        let angled = [tilted("That was quite a", 0.1, 0.20, 0.75), tilted("surprise!", 0.1, 0.237, 0.35),
                      tilted("Did you see it?", 0.1, 0.325, 0.70), tilted("Ask later", 0.52, 0.78, 0.88),
                      tilted("No problem", 0.50, 0.862, 0.88)]
        let groups = GamePhoneText.groups(Reading(lines: angled))
        XCTAssertEqual(groups.flatMap(\.paragraphs), ["That was quite a surprise!", "Did you see it?", "Ask later", "No problem"])
        XCTAssertEqual(groups.first?.box, angled[0].box!.union(angled[1].box!))
    }

    /// Önizlemenin üç noktası tek yazımla; son sözcük tamamlanmaz (Windows ile aynı).
    func testPreviewEllipsisHasOneSpellingWithoutCompletingTheLastWord() {
        for (preview, expected) in [("Meet me there ..", "Meet me there..."), ("Meet me there ...", "Meet me there..."),
                                    ("Meet me there...", "Meet me there..."), ("Meet me at 6.", "Meet me at 6.")] {
            let reading = Reading(lines: [line("Suggested", 0.02), line("Jordan", 0.10), line(preview, 0.14),
                                          line("Chase", 0.22), line("Call me back.", 0.26), line("Messages", 0.40),
                                          line("Robin", 0.50), line("On my way.", 0.54)])
            XCTAssertTrue(GamePhoneText.forTranslation(reading).lines.contains { $0.text == expected }, preview)
        }
    }

    /// Yan yana iki kısa sözcükte birer harf oynaması OCR sapmasıdır; kısa yanıtlar ve anlam değişiklikleri değildir.
    func testOnlyAdjacentLetterSlipsInALongMessageWaitForOcrConfirmation() {
        XCTAssertTrue(GamePhoneText.hasAdjacentOcrEdits("Cool. I'll check it out. Would be nice to clear my head for a second.",
                                                        "Cool. I'll check ct ocut. Would be nice to clear my head for a second."))
        for (old, next) in [("Go", "No"),
                            ("Meet me at the back gate with 24 red bags.", "Meet me at the back gate with 25 bed bags."),
                            ("We can do it now if you bring the truck.", "We can not do it now if you bring the truck."),
                            ("I heard they all went to the left door.", "I heard they all went to the rear door."),
                            ("That was all I needed to hear from your friend.", "The next message just came in from the office.")] {
            XCTAssertFalse(GamePhoneText.hasAdjacentOcrEdits(old, next), next)
        }
    }

    /// Doğrulanmış listede "Okay" gibi tek sözcüklük önizleme başka bir kişi adı sanılmaz.
    func testSingleWordPreviewInAConfirmedListIsNotMistakenForAnotherContact() {
        for message in ["Okay", "No", "Thanks"] {
            let rows = Reading(lines: [line("Suggestions", 0.02), line("Chase", 0.09), line("call me soon", 0.13),
                                       line("May", 0.21), line("Don't leave yet.", 0.25), line("Messages", 0.34),
                                       line("Rose", 0.42), line("Meet me here.", 0.46), line("Jason", 0.56), line(message, 0.60),
                                       line("Martin", 0.73), line("Lucia", 0.85)])
            let kept = GamePhoneText.forTranslation(rows).lines
            XCTAssertEqual(kept.map(\.text), ["Suggestions", "Chase", "call me soon", "May", "Don't leave yet.", "Messages",
                                              "Rose", "Meet me here.", "Jason", message, "Martin", "Lucia"])
            XCTAssertEqual(kept.first { $0.text == message }?.listRole, .preview)
            XCTAssertEqual(kept.filter { $0.listRole == .contact }.map(\.text), ["Chase", "May", "Rose", "Jason", "Martin", "Lucia"])
        }
    }

    /// Aynı taraftaki ayrı yanıtlar telefon kıpırdarken de ayrı kalır; cümleden sonra alt satıra geçen ikinci cümle birliktedir.
    func testSameSideRepliesRemainSeparateAsThePhoneMoves() {
        let h = 0.04
        func flat(_ text: String, _ y: Double, _ x: Double) -> TextLine {
            let box = TextBox(left: x, top: y, right: 0.8, bottom: y + h)
            var row = TextLine(text, box: box)
            row.phoneBox = box
            return row
        }
        for spacing in [0.72, 1.03] {
            let y = 0.12 + h * (1 + spacing), next = y + h * (2.1 + spacing)
            let reading = Reading(lines: [flat("Jason.", 0.12, 0.10), flat("Kirk is paying.", y, 0.15),
                                          flat("He is on his way.", y + h * 1.10, 0.15), flat("Meet me outside.", next, 0.10)])
            XCTAssertEqual(GamePhoneText.groups(reading).flatMap(\.paragraphs),
                           ["Jason.", "Kirk is paying. He is on his way.", "Meet me outside."], "\(spacing)")
        }
    }
}
