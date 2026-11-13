import Foundation

struct Language: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

enum Languages {
    static let autoCode = "auto"

    /// Коды — как у Google. Для Яндекса конвертируются через `yandexCode`.
    static let all: [Language] = raw
        .map { Language(code: $0.0, name: $0.1) }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

    private static let raw: [(String, String)] = [
        ("af", "Африкаанс"), ("sq", "Албанский"), ("am", "Амхарский"), ("ar", "Арабский"),
        ("hy", "Армянский"), ("az", "Азербайджанский"), ("ba", "Башкирский"), ("eu", "Баскский"),
        ("be", "Белорусский"), ("bn", "Бенгальский"), ("bs", "Боснийский"), ("bg", "Болгарский"),
        ("my", "Бирманский"), ("ca", "Каталанский"), ("ceb", "Себуанский"), ("zh-CN", "Китайский (упрощ.)"),
        ("zh-TW", "Китайский (традиц.)"), ("co", "Корсиканский"), ("hr", "Хорватский"), ("cs", "Чешский"),
        ("cv", "Чувашский"), ("da", "Датский"), ("nl", "Нидерландский"), ("en", "Английский"),
        ("eo", "Эсперанто"), ("et", "Эстонский"), ("fi", "Финский"), ("fr", "Французский"),
        ("fy", "Фризский"), ("gl", "Галисийский"), ("ka", "Грузинский"), ("de", "Немецкий"),
        ("el", "Греческий"), ("gu", "Гуджарати"), ("ht", "Гаитянский"), ("ha", "Хауса"),
        ("haw", "Гавайский"), ("iw", "Иврит"), ("hi", "Хинди"), ("hmn", "Хмонг"),
        ("hu", "Венгерский"), ("is", "Исландский"), ("ig", "Игбо"), ("id", "Индонезийский"),
        ("ga", "Ирландский"), ("it", "Итальянский"), ("ja", "Японский"), ("jw", "Яванский"),
        ("kn", "Каннада"), ("kk", "Казахский"), ("km", "Кхмерский"), ("ko", "Корейский"),
        ("ku", "Курдский"), ("ky", "Киргизский"), ("lo", "Лаосский"), ("la", "Латинский"),
        ("lv", "Латышский"), ("lt", "Литовский"), ("lb", "Люксембургский"), ("mk", "Македонский"),
        ("mg", "Малагасийский"), ("ms", "Малайский"), ("ml", "Малаялам"), ("mt", "Мальтийский"),
        ("mi", "Маори"), ("mr", "Маратхи"), ("mn", "Монгольский"), ("ne", "Непальский"),
        ("no", "Норвежский"), ("ny", "Чева"), ("ps", "Пушту"), ("fa", "Персидский"),
        ("pl", "Польский"), ("pt", "Португальский"), ("pa", "Панджаби"), ("ro", "Румынский"),
        ("ru", "Русский"), ("sah", "Якутский"), ("sm", "Самоанский"), ("gd", "Гэльский"),
        ("sr", "Сербский"), ("st", "Сесото"), ("sn", "Шона"), ("sd", "Синдхи"),
        ("si", "Сингальский"), ("sk", "Словацкий"), ("sl", "Словенский"), ("so", "Сомали"),
        ("es", "Испанский"), ("su", "Сунданский"), ("sw", "Суахили"), ("sv", "Шведский"),
        ("tl", "Тагальский"), ("tg", "Таджикский"), ("ta", "Тамильский"), ("tt", "Татарский"),
        ("te", "Телугу"), ("th", "Тайский"), ("tr", "Турецкий"), ("tk", "Туркменский"),
        ("uk", "Украинский"), ("ur", "Урду"), ("ug", "Уйгурский"), ("uz", "Узбекский"),
        ("vi", "Вьетнамский"), ("cy", "Валлийский"), ("xh", "Коса"), ("yi", "Идиш"),
        ("yo", "Йоруба"), ("zu", "Зулу"),
    ]

    /// Приводит разные написания кода к одному виду, чтобы их можно было сравнивать.
    static func normalize(_ code: String) -> String {
        let c = code.lowercased().replacingOccurrences(of: "_", with: "-")
        switch c {
        case "he": return "iw"
        case "jv": return "jw"
        case "zh", "zh-hans", "zh-cn": return "zh-cn"
        case "zh-hant", "zh-tw": return "zh-tw"
        case "nb", "nn": return "no"
        case "fil": return "tl"
        default: return c
        }
    }

    static func same(_ a: String, _ b: String) -> Bool { normalize(a) == normalize(b) }

    static func language(_ code: String) -> Language? {
        let n = normalize(code)
        return all.first { normalize($0.code) == n }
    }

    static func name(_ code: String) -> String {
        if code == autoCode { return "Автоопределение" }
        return language(code)?.name ?? code
    }

    static func short(_ code: String) -> String {
        if code == autoCode { return "АВТО" }
        return code.uppercased()
    }

    /// Канонический код (как в списке `all`).
    static func canonical(_ code: String) -> String {
        language(code)?.code ?? code
    }

    static func yandexCode(_ code: String) -> String {
        switch normalize(code) {
        case "zh-cn", "zh-tw": return "zh"
        case "iw": return "he"
        case "jw": return "jv"
        default: return code.lowercased()
        }
    }

    static func fromYandex(_ code: String) -> String {
        switch code.lowercased() {
        case "zh": return "zh-CN"
        case "he": return "iw"
        case "jv": return "jw"
        default: return canonical(code)
        }
    }

    /// Код для системного синтезатора речи (AVSpeechSynthesizer).
    static func speechLocale(_ code: String) -> String {
        switch normalize(code) {
        case "iw": return "he-IL"
        case "zh-cn": return "zh-CN"
        case "zh-tw": return "zh-TW"
        case "jw": return "jv"
        case "en": return "en-US"
        case "ru": return "ru-RU"
        default: return code
        }
    }
}
