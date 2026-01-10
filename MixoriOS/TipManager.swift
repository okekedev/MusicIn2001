//
//  TipManager.swift
//  MixoriOS
//

import StoreKit

@Observable
@MainActor
final class TipManager {
    static let shared = TipManager()

    // Product IDs - these need to match App Store Connect
    static let productIDs: [String] = [
        "com.christianokeke.MyMusic.tip1",
        "com.christianokeke.MyMusic.tip5",
        "com.christianokeke.MyMusic.tip20",
        "com.christianokeke.MyMusic.tip100"
    ]

    var products: [Product] = []
    var purchaseInProgress = false
    var purchaseResult: String?

    private init() {
        Task {
            await loadProducts()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: TipManager.productIDs)
            products.sort { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async -> Bool {
        purchaseInProgress = true
        purchaseResult = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    purchaseInProgress = false
                    purchaseResult = "Thank you!"
                    return true
                case .unverified:
                    purchaseInProgress = false
                    purchaseResult = "Verification failed"
                    return false
                }
            case .userCancelled:
                purchaseInProgress = false
                return false
            case .pending:
                purchaseInProgress = false
                purchaseResult = "Pending..."
                return false
            @unknown default:
                purchaseInProgress = false
                return false
            }
        } catch {
            purchaseInProgress = false
            purchaseResult = "Error"
            return false
        }
    }

    // Fallback display prices if products haven't loaded
    func displayPrice(for productID: String) -> String {
        if let product = products.first(where: { $0.id == productID }) {
            return product.displayPrice
        }
        // Fallback prices
        switch productID {
        case "com.christianokeke.MyMusic.tip1": return "$0.99"
        case "com.christianokeke.MyMusic.tip5": return "$4.99"
        case "com.christianokeke.MyMusic.tip20": return "$19.99"
        case "com.christianokeke.MyMusic.tip100": return "$99.99"
        default: return ""
        }
    }

    func product(for productID: String) -> Product? {
        products.first { $0.id == productID }
    }
}
