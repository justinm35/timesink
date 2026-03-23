import Foundation

/// CRUD operations for user-defined categories.
///
/// Wraps the database category methods and provides additional convenience.
@MainActor
final class CategoryStore: Observable {

    private let database: AppDatabase

    /// All categories, kept in sync with the database.
    private(set) var categories: [Category] = []

    var hasRealmCategories: Bool {
        categories.contains { $0.realm != nil }
    }

    init(database: AppDatabase) {
        self.database = database
        refreshCategories()
    }

    /// Reloads categories from the database.
    func refreshCategories() {
        do {
            categories = try database.fetchAllCategories()
        } catch {
            print("Failed to fetch categories: \(error)")
        }
    }

    /// Adds a new category.
    func addCategory(name: String, description: String, color: String, isProductive: Bool, realm: String? = nil) {
        let sortOrder = (categories.last?.sortOrder ?? -1) + 1
        let category = Category(
            name: name,
            description: description,
            color: color,
            isProductive: isProductive,
            realm: realm,
            sortOrder: sortOrder
        )

        do {
            _ = try database.saveCategory(category)
            refreshCategories()
        } catch {
            print("Failed to add category: \(error)")
        }
    }

    /// Updates an existing category.
    func updateCategory(_ category: Category) {
        do {
            _ = try database.saveCategory(category)
            refreshCategories()
        } catch {
            print("Failed to update category: \(error)")
        }
    }

    /// Deletes a category by ID.
    func deleteCategory(id: Int64) {
        do {
            try database.deleteCategory(id: id)
            refreshCategories()
        } catch {
            print("Failed to delete category: \(error)")
        }
    }

    /// Reorders categories to match the given ID order.
    func reorder(_ orderedIds: [Int64]) {
        do {
            try database.reorderCategories(orderedIds)
            refreshCategories()
        } catch {
            print("Failed to reorder categories: \(error)")
        }
    }

    /// Resets categories to defaults (deletes all and re-seeds).
    func resetToDefaults() {
        do {
            for category in categories {
                if let id = category.id {
                    try database.deleteCategory(id: id)
                }
            }
            for defaultCategory in Category.defaults {
                _ = try database.saveCategory(defaultCategory)
            }
            refreshCategories()
        } catch {
            print("Failed to reset categories: \(error)")
        }
    }
}
