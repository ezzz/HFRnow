import Foundation
import Testing
@testable import HFRModels

@Suite struct ForumFormTests {
    private func makeForm() -> ForumForm {
        ForumForm(
            action: "/bddpost.php",
            fields: [
                FormField(name: "hash_check", value: "x", kind: .hidden),
                FormField(name: "sujet", value: "", kind: .text),
                FormField(name: "dest", value: "Bob", kind: .hidden),
                FormField(name: "MsgIcon", value: "1", kind: .radio, isChecked: true)
            ],
            selects: [FormSelect(name: "subcat", options: [FormOption(value: "0", label: "-"), FormOption(value: "2", label: "Divers")])],
            textareaContent: "[quotemsg=1,2,3]x[/quotemsg]",
            dynamicSmileys: [ForumSmiley(
                code: "[:ezzz]",
                url: URL(string: "https://forum-images.hardware.fr/images/perso/1/a%20b.gif") ?? URL(fileURLWithPath: "/")
            )]
        )
    }

    @Test func roundTrips() throws {
        let form = makeForm()
        #expect(try roundTrip(form) == form)
    }

    @Test func subjectIsEditableOnlyWhenVisible() {
        var form = makeForm()
        #expect(form.isSubjectEditable)
        form.fields[1].kind = .hidden
        #expect(!form.isSubjectEditable)
        form.fields.remove(at: 1)
        #expect(!form.isSubjectEditable)
    }

    @Test func subcategoriesComeFromTheSubcatSelect() {
        var form = makeForm()
        #expect(form.isSubcategoryEditable)
        #expect(form.subcategories.map(\.value) == ["0", "2"])
        form.selects = []
        #expect(!form.isSubcategoryEditable)
        #expect(form.subcategories.isEmpty)
    }

    @Test func lookupsAreByNameAndRecipientIsExposed() {
        let form = makeForm()
        #expect(form.field(named: "hash_check")?.kind == .hidden)
        #expect(form.field(named: "missing") == nil)
        #expect(form.recipient == "Bob")
        #expect(ForumForm().recipient == nil)
    }

    @Test func selectEffectiveValuePrefersSelectionThenFirstOption() {
        let options = [FormOption(value: "a", label: "A"), FormOption(value: "b", label: "B")]
        #expect(FormSelect(name: "s", options: options, selectedValue: "b").effectiveValue == "b")
        #expect(FormSelect(name: "s", options: options).effectiveValue == "a")
        #expect(FormSelect(name: "s").effectiveValue == nil)
    }

    @Test(arguments: [
        (nil, FormInputKind.text), ("", .text), ("TEXT", .text), ("Hidden", .hidden), ("checkbox", .checkbox),
        ("radio", .radio), ("submit", .submit), ("password", .password), ("file", .other), ("other", .other)
    ] as [(String?, FormInputKind)])
    func inputKindsMapFromHTMLTypes(type: String?, expected: FormInputKind) {
        #expect(FormInputKind(htmlType: type) == expected)
    }

    @Test func checkedStateParticipatesInEquality() {
        #expect(FormField(name: "a", kind: .checkbox, isChecked: true) != FormField(name: "a", kind: .checkbox))
    }

    @Test func diagnosticsRedactHiddenAndPasswordValuesButNotVisibleOnes() {
        let form = ForumForm(fields: [
            FormField(name: "hash_check", value: "TOKEN-SECRET", kind: .hidden),
            FormField(name: "password", value: "PASSWORD-SECRET", kind: .password),
            FormField(name: "sujet", value: "visible subject", kind: .text)
        ])
        var dumped = ""
        dump(form, to: &dumped)
        for output in [form.fields[0].description, form.fields[1].debugDescription, "\(form)", String(reflecting: form), dumped] {
            #expect(!output.contains("SECRET"))
        }
        #expect(form.fields[2].description.contains("visible subject"))
        #expect(dumped.contains("visible subject"))
    }
}
