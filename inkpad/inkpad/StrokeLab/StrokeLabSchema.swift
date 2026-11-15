import Foundation
import CoreFoundation

/// Evaluates the JSON Schema vocabulary used by our bundled v1 contract.
/// Unsupported keywords must be implemented here before adding them to the schema.
nonisolated enum StrokeLabSchema {
    static func validate(raw: Data, annotations: Data) throws {
        guard let url = Bundle.main.url(forResource: "stroke-lab-v1.schema", withExtension: "json"),
              let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw LabError.invalid("Missing shared Stroke Lab schema")
        }
        let value: [String: Any] = ["raw": try JSONSerialization.jsonObject(with: raw),
                                   "annotations": try JSONSerialization.jsonObject(with: annotations)]
        try check(value, schema: schema, root: schema, path: "page")
    }

    private static func check(_ value: Any, schema: [String: Any], root: [String: Any], path: String) throws {
        func fail(_ message: String) throws { throw LabError.invalid("\(path): \(message)") }
        let supported: Set<String> = ["$schema", "$id", "title", "$defs", "$ref", "type", "const", "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "uniqueItems", "minLength", "minimum", "exclusiveMinimum", "maximum"]
        guard Set(schema.keys).isSubset(of: supported) else { try fail("Unsupported schema keyword"); return }
        if let ref = schema["$ref"] as? String {
            let name = String(ref.dropFirst("#/$defs/".count))
            guard let definitions = root["$defs"] as? [String: Any], let target = definitions[name] as? [String: Any] else { try fail("Unknown schema reference"); return }
            try check(value, schema: target, root: root, path: path)
            return
        }
        if let constant = schema["const"] as? String, (value as? String) != constant { try fail("Unexpected constant") }
        switch schema["type"] as? String {
        case "object":
            guard let object = value as? [String: Any], let properties = schema["properties"] as? [String: [String: Any]] else { try fail("Expected object"); return }
            for key in schema["required"] as? [String] ?? [] where object[key] == nil { try fail("Missing \(key)") }
            if schema["additionalProperties"] as? Bool == false && !Set(object.keys).isSubset(of: Set(properties.keys)) { try fail("Unknown field") }
            for (key, item) in object {
                if let property = properties[key] { try check(item, schema: property, root: root, path: path + "." + key) }
            }
        case "array":
            guard let array = value as? [Any], let items = schema["items"] as? [String: Any] else { try fail("Expected array"); return }
            if let min = schema["minItems"] as? Int, array.count < min { try fail("Too few elements") }
            if let max = schema["maxItems"] as? Int, array.count > max { try fail("Too many elements") }
            if schema["uniqueItems"] as? Bool == true {
                let strings = array.compactMap { $0 as? String }
                guard strings.count == array.count, Set(strings).count == array.count else { try fail("Duplicate or unsupported unique element"); return }
            }
            for (i, item) in array.enumerated() { try check(item, schema: items, root: root, path: "\(path)[\(i)]") }
        case "string":
            guard let string = value as? String else { try fail("Expected string"); return }
            if let min = schema["minLength"] as? Int, string.count < min { try fail("String too short") }
        case "number", "integer":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { try fail("Expected finite number"); return }
            let n = number.doubleValue
            if schema["type"] as? String == "integer" && n.rounded() != n { try fail("Expected integer") }
            if let min = schema["minimum"] as? Double, n < min { try fail("Below minimum") }
            if let min = schema["exclusiveMinimum"] as? Double, n <= min { try fail("Below exclusive minimum") }
            if let max = schema["maximum"] as? Double, n > max { try fail("Above maximum") }
        case nil: break
        default: try fail("Unsupported schema type")
        }
    }
}
