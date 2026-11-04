import Foundation
import WhoopStore

// Personal fork (2 Nov 2026): a scanned barcode the journal does not know yet is looked up on Open Food
// Facts, the open food products database (no account, no key). Only the barcode is sent, and only when
// the wearer scans one with the setting on (on by default, Nutrition → Goals). The product it returns is
// shown with its values for 100 g to check before "Add to journal"; once added, the journal line keeps
// them (`foodRef = "ean:<code>"`) and the next scan finds it on the iPhone with no request. A product
// Open Food Facts does not have, or no network, falls back to the label read by the Coach.
// Fork chantier 9: the food search of Nutrition can also ask it for products by the words typed
// (`searchProducts`), only when the wearer taps the line that asks for it; only those words are sent.
// Data: Open Food Facts contributors, Open Database License (ODbL).

enum OpenFoodFacts {

    /// The setting (UserDefaults, outside the `.noopbak`): look a new barcode up on Open Food Facts.
    static let enabledKey = "nutrition.openFoodFactsEnabled"
    /// On unless the wearer turned it off.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Credit shown with a product that came from it.
    static let attribution = "Open Food Facts (ODbL)"
    /// The request gives up after this long: the label read by the Coach is the fallback.
    static let timeoutSeconds: TimeInterval = 8
    /// Open Food Facts asks every app to name itself.
    static let userAgent = "NOOP-personal-fork/1.0 (iOS; nutrition journal)"

    /// What a lookup gave.
    enum Lookup: Equatable {
        case found(BarcodeProduct)
        /// Open Food Facts answered but has no usable product (unknown, or no values for 100 g).
        case notFound
        /// No answer: offline, timed out, or an error.
        case unreachable
    }

    /// The product request: only the fields used (name, brand, nutriments).
    static func productURL(barcode: String) -> URL? {
        var parts = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")
        parts?.queryItems = [URLQueryItem(name: "fields", value: "code,product_name,product_name_fr,brands,nutriments")]
        return parts?.url
    }

    /// The product in an Open Food Facts answer, or nil when it has none or its values are not usable.
    /// Energy: the kcal per 100 g, else the kJ ÷ 4.184, else 4/4/9 from the macros; refused like a label
    /// read by the Coach (protein + carbs + fat over 102 g, or over 900 kcal, for 100 g).
    static func parseProduct(_ data: Data, barcode: String) -> BarcodeProduct? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (number(root["status"]) ?? 0) == 1,
              let product = root["product"] as? [String: Any] else { return nil }
        return productFields(product, barcode: barcode)
    }

    /// One product object (the `product` of a lookup, or an item of a search) as a usable product, or nil.
    static func productFields(_ product: [String: Any], barcode: String) -> BarcodeProduct? {
        guard let nutriments = product["nutriments"] as? [String: Any] else { return nil }
        guard let protein = number(nutriments["proteins_100g"]),
              let carbs = number(nutriments["carbohydrates_100g"]),
              let fat = number(nutriments["fat_100g"]),
              [protein, carbs, fat].allSatisfy({ $0 >= 0 }) else { return nil }
        let kcal: Double
        if let k = number(nutriments["energy-kcal_100g"]), k > 0 {
            kcal = k
        } else if let kj = number(nutriments["energy-kj_100g"]) ?? number(nutriments["energy_100g"]), kj > 0 {
            kcal = kj / CoachMealProposal.kilojoulesPerKcal
        } else {
            kcal = Double(MealMath.kcal(proteinG: protein, carbsG: carbs, fatG: fat))
        }
        guard protein + carbs + fat <= CoachMealProposal.labelMacroCeiling,
              CoachMealProposal.labelKcalRange.contains(kcal) else { return nil }
        let name = productName(product)
        guard !name.isEmpty else { return nil }
        let per100 = MealPer100(kcal: MealMath.tenth(kcal), proteinG: MealMath.tenth(protein),
                                carbsG: MealMath.tenth(carbs), fatG: MealMath.tenth(fat))
        return BarcodeProduct(barcode: barcode, name: name, per100: per100, lastGrams: nil, lastEatenAt: 0,
                              source: .openFoodFacts)
    }

    /// "Skyr nature · Siggi's": the French name, else the generic one, then the first brand; 60 characters.
    static func productName(_ product: [String: Any]) -> String {
        func text(_ key: String) -> String? {
            guard let raw = (product[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            return raw
        }
        guard let name = text("product_name_fr") ?? text("product_name") else { return "" }
        let brand = text("brands")?.split(separator: ",").first.map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let full = brand.flatMap { $0.isEmpty || name.localizedCaseInsensitiveContains($0) ? nil : name + " · " + $0 } ?? name
        return String(full.prefix(60))
    }

    /// Ask Open Food Facts for `barcode`. Only the barcode leaves the iPhone.
    static func lookupProduct(barcode: String, session: URLSession = .shared) async -> Lookup {
        guard let url = productURL(barcode: barcode) else { return .unreachable }
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return .notFound }
            guard (200..<300).contains(status) else { return .unreachable }
            return parseProduct(data, barcode: barcode).map(Lookup.found) ?? .notFound
        } catch {
            return .unreachable
        }
    }

    // MARK: Search by words (fork chantier 9)

    /// Most products a search lists.
    static let searchPageSize = 20

    /// What a search by words gave.
    enum WordSearch: Equatable {
        case found([BarcodeProduct])
        /// No answer: offline, timed out, or an error.
        case unreachable
    }

    /// The search request: the words typed, and only the fields used. Open Food Facts limits searches to
    /// about ten a minute, so the app sends one only when the wearer taps the line that asks for it.
    static func searchURL(terms: String) -> URL? {
        var parts = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        parts?.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(searchPageSize)),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_fr,brands,nutriments"),
        ]
        return parts?.url
    }

    /// The usable products of a search answer, in its order: a product needs a barcode (8 to 14 digits)
    /// and values for 100 g, read like a scanned one (`productFields`); one barcode once.
    static func parseSearch(_ data: Data) -> [BarcodeProduct] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let products = root["products"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        var found: [BarcodeProduct] = []
        for product in products {
            guard let raw = product["code"] as? String, let code = BarcodeCatalog.normalizedBarcode(raw),
                  !seen.contains(code), let usable = productFields(product, barcode: code) else { continue }
            seen.insert(code)
            found.append(usable)
        }
        return found
    }

    /// Ask Open Food Facts for the products matching `terms`. Only the words typed leave the iPhone.
    static func searchProducts(terms: String, session: URLSession = .shared) async -> WordSearch {
        let trimmed = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = searchURL(terms: trimmed) else { return .found([]) }
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return .unreachable }
            return .found(parseSearch(data))
        } catch {
            return .unreachable
        }
    }

    /// A JSON number, or a number written as text ("12,5" too).
    private static func number(_ raw: Any?) -> Double? {
        if let n = raw as? NSNumber { return n.doubleValue.isFinite ? n.doubleValue : nil }
        if let s = raw as? String, let v = Double(s.replacingOccurrences(of: ",", with: ".")), v.isFinite { return v }
        return nil
    }
}
