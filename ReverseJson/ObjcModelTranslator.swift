
public class ObjcModelCreator: ModelTranslator {
    
    public required init(args: [String] = []) {}
    
    private let atomic = false
    private let readonly = true
    private let typePrefix = "TSA"
    private var atomicyModifier: String {
        return (atomic ? "atomic" : "nonatomic")
    }
    
    public func translate(type: ModelParser.FieldType, name: String) -> String {
        let a = declarationsFor(type, name: name, valueToParse: "jsonValue")
        var ret = "#import <Foundation/Foundation.h>\n\n"
        ret += a.interfaces.joinWithSeparator("\n\n")
        ret += "\n\n"
        ret += a.implementations.joinWithSeparator("\n\n")
        return ret
    }
    
    public func isNullable(type: ModelParser.FieldType) -> Bool {
        switch type {
        case .Optional:
            return true
        default:
            return false
        }
    }
    
    public func hasPointerStar(type: ModelParser.FieldType) -> Bool {
        switch type {
        case .Number, .Unknown, .Optional(.Unknown):
            return false
        default:
            return true
        }
    }
    
    func memoryManagementModifier(type: ModelParser.FieldType) -> String {
        switch type {
        case .Optional(.Number), .Text:
            return "copy"
        case .Number:
            return "assign"
        default:
            return "strong"
        }
    }
    
    private func declarationsFor(type: ModelParser.FieldType, name: String, valueToParse: String) -> (interfaces: Set<String>, implementations: Set<String>, parseExpression: String, fieldRequiredTypeNames: Set<String>, fullTypeName: String) {
        switch type {
        case let .Enum(enumTypes):
            let className = "\(typePrefix)\(name.camelCasedString)"
            let fieldValues = enumTypes.map { type -> (property: String, initialization: String, requiredTypeNames: Set<String>, fieldTypeName: String, interfaces: Set<String>, implementations: Set<String>) in
                let nullable = isNullable(type)
                
                let (subInterfaces, subImplementations, parseExpression, fieldRequiredTypeNames, fieldFullTypeName) = declarationsFor(type, name: "\(name.camelCasedString)\(type.enumCaseName.camelCasedString)", valueToParse: "jsonValue")
                
                var modifiers = [atomicyModifier, memoryManagementModifier(type)]
                if (readonly) {
                    modifiers.append("readonly")
                }
                if nullable {
                    modifiers.append("nullable")
                }
                let modifierList = modifiers.joinWithSeparator(", ")
                let variableName = type.enumCaseName.pascalCasedString
                let propertyName: String
                if fieldFullTypeName.hasSuffix("*") {
                    propertyName = variableName
                } else {
                    propertyName = " \(variableName)"
                }
                let property = "@property (\(modifierList)) \(fieldFullTypeName)\(propertyName);"
                let initialization = "_\(variableName) = \(parseExpression);"
                return (property, initialization, fieldRequiredTypeNames, fieldFullTypeName, subInterfaces, subImplementations)
            }
            let requiredTypeNames = Set(fieldValues.flatMap{$0.requiredTypeNames})
            let forwardDeclarations = requiredTypeNames.sort(<)
            let properties = fieldValues.sort{$0.0.fieldTypeName < $0.1.fieldTypeName}.map {$0.property}
            let initializations = fieldValues.sort{$0.0.fieldTypeName < $0.1.fieldTypeName}.map {$0.initialization.indent(2)}
            
            var interface = ""
            if !forwardDeclarations.isEmpty {
                let forwardDeclarationList = forwardDeclarations.joinWithSeparator(", ")
                interface += "@class \(forwardDeclarationList);\n"
            }
            interface += ([
                "NS_ASSUME_NONNULL_BEGIN",
                "@interface \(className) : NSObject",
                "- (nullable instancetype)initWithJsonValue:(nullable id<NSObject>)jsonValue;",
            ] + properties + [
                "@end",
                "NS_ASSUME_NONNULL_END",
            ]).joinWithSeparator("\n")
            
            let implementation = ([
                "@implementation \(className)",
                "- (instancetype)initWithJsonValue:(id)jsonValue {",
                "    self = [super init];",
                "    if (self) {",
            ] + initializations + [
                "    }",
                "    return self;",
                "}",
                "@end",
            ]).joinWithSeparator("\n")
            
            let interfaces = fieldValues.lazy.map {$0.interfaces}.reduce(Set([interface])) { $0.union($1) }
            let implementations = fieldValues.lazy.map{$0.implementations}.reduce(Set([implementation])) { $0.union($1) }
            let parseExpression = "[[\(className) alloc] initWithJsonValue:\(valueToParse)]"
            return (interfaces, implementations, parseExpression, [className], "\(className) *")
            
        case let .Object(fields):
            let className = "\(typePrefix)\(name.camelCasedString)"
            let fieldValues = fields.map { field -> (property: String, initialization: String, requiredTypeNames: Set<String>, fieldTypeName: String, interfaces: Set<String>, implementations: Set<String>) in
                let nullable = isNullable(field.type)
                
                let valueToParse = "dict[@\"\(field.name)\"]"
                let (subInterfaces, subImplementations, parseExpression, fieldRequiredTypeNames, fieldFullTypeName) = declarationsFor(field.type, name: "\(name.camelCasedString)\(field.name.camelCasedString)", valueToParse: valueToParse)

                var modifiers = [atomicyModifier, memoryManagementModifier(field.type)]
                if (readonly) {
                    modifiers.append("readonly")
                }
                if nullable {
                    modifiers.append("nullable")
                }
                let modifierList = modifiers.joinWithSeparator(", ")
                let variableName = field.name.pascalCasedString
                let propertyName: String
                if fieldFullTypeName.hasSuffix("*") {
                    propertyName = variableName
                } else {
                    propertyName = " \(variableName)"
                }
                let property = "@property (\(modifierList)) \(fieldFullTypeName)\(propertyName);"
                let initialization = "_\(variableName) = \(parseExpression);"
                return (property, initialization, fieldRequiredTypeNames, fieldFullTypeName, subInterfaces, subImplementations)
            }
            let requiredTypeNames = Set(fieldValues.flatMap{$0.requiredTypeNames})
            let forwardDeclarations = requiredTypeNames.sort(<)
            let properties = fieldValues.sort{$0.0.fieldTypeName < $0.1.fieldTypeName}.map {$0.property}
            let initializations = fieldValues.sort{$0.0.fieldTypeName < $0.1.fieldTypeName}.map {$0.initialization.indent(2)}
            
            var interface = ""
            if !forwardDeclarations.isEmpty {
                let forwardDeclarationList = forwardDeclarations.joinWithSeparator(", ")
                interface += "@class \(forwardDeclarationList);\n"
            }
            interface += ([
                "NS_ASSUME_NONNULL_BEGIN",
                "@interface \(className) : NSObject",
                "- (instancetype)initWithJsonDictionary:(NSDictionary<NSString *, id<NSObject>> *)dictionary;",
                "- (nullable instancetype)initWithJsonValue:(nullable id<NSObject>)jsonValue;",
            ] + properties + [
                "@end",
                "NS_ASSUME_NONNULL_END"
            ]).joinWithSeparator("\n")
            
            let implementation = ([
                "@implementation \(className)",
                "- (instancetype)initWithJsonDictionary:(NSDictionary<NSString *, id> *)dict {",
                "    self = [super init];",
                "    if (self) {",
            ] + initializations + [
                "    }",
                "    return self;",
                "}",
                "- (instancetype)initWithJsonValue:(id)jsonValue {",
                "    if ([jsonValue isKindOfClass:[NSDictionary class]]) {",
                "        self = [self initWithJsonDictionary:jsonValue];",
                "    } else {",
                "        self = nil;",
                "    }",
                "    return self;",
                "}",
                "@end",
            ]).joinWithSeparator("\n")
            
            let interfaces = fieldValues.lazy.map {$0.interfaces}.reduce(Set([interface])) { $0.union($1) }
            let implementations = fieldValues.lazy.map{$0.implementations}.reduce(Set([implementation])) { $0.union($1) }
            let parseExpression = "[[\(className) alloc] initWithJsonValue:\(valueToParse)]"
            return (interfaces, implementations, parseExpression, [className], "\(className) *")
        case .Text:
            return ([], [], "[\(valueToParse) isKindOfClass:[NSString class]] ? \(valueToParse) : nil", [], "NSString *")
        case let .Number(numberType):
            return ([], [], "[\(valueToParse) isKindOfClass:[NSNumber class]] ? [\(valueToParse) \(numberType.objcNSNumberMethod)] : 0", [], numberType.objcNumberType)
        case var .List(listType):
            if case let .Number(numberType) = listType {
                listType = .Optional(.Number(numberType))
            }
            let subName: String
            if case .List = listType {
                subName = name
            } else {
                subName = "\(name)Item"
            }
            let listTypeValues = declarationsFor(listType, name: subName, valueToParse: "item")
            let subParseExpression: String
            if let lineBreakRange = listTypeValues.parseExpression.rangeOfString("\n") {
                let firstLine = listTypeValues.parseExpression.substringToIndex(lineBreakRange.startIndex)
                let remainingLines = listTypeValues.parseExpression.substringFromIndex(lineBreakRange.startIndex).indent(3)
                subParseExpression = "\(firstLine)\n\(remainingLines)"
            } else {
                subParseExpression = listTypeValues.parseExpression;
            }
            let listTypeName: String
            if listTypeValues.fullTypeName.hasSuffix("*") {
                listTypeName = listTypeValues.fullTypeName
            } else {
                listTypeName = "\(listTypeValues.fullTypeName) "
            }
            let parseExpression = [
                "({",
                "    id value = \(valueToParse);",
                "    NSMutableArray<\(listTypeValues.fullTypeName)> *values = nil;",
                "    if ([value isKindOfClass:[NSArray class]]) {",
                "        NSArray *array = value;",
                "        values = [NSMutableArray arrayWithCapacity:array.count];",
                "        for (id item in array) {",
                "            \(listTypeName)parsedItem = \(subParseExpression);",
                "            [values addObject:parsedItem ?: (id)[NSNull null]];",
                "        }",
                "    }",
                "    [values copy];",
                "})"
            ].joinWithSeparator("\n")
            return (listTypeValues.interfaces, listTypeValues.implementations, parseExpression, listTypeValues.fieldRequiredTypeNames, "NSArray<\(listTypeValues.fullTypeName)> *")
        case let .Optional(.Number(numberType)):
            return ([], [], "[\(valueToParse) isKindOfClass:[NSNumber class]] ? \(valueToParse) : nil", [], "NSNumber/*\(numberType.objcNumberType)*/ *")
        case .Optional(let optionalType):
            return declarationsFor(optionalType, name: name, valueToParse: valueToParse)
        case .Unknown:
            return ([], [], valueToParse, [], "id<NSObject>")
        }
    }
    
}

extension ModelParser.NumberType {
    private var objcNumberType: String {
        switch self {
        case .Bool: return "BOOL"
        case .Int: return "NSInteger"
        case .Float: return "float"
        case .Double: return "double"
        }
    }
    private var objcNSNumberMethod: String {
        switch self {
        case .Bool: return "boolValue"
        case .Int: return "integerValue"
        case .Float: return "floatValue"
        case .Double: return "doubleValue"
        }
    }
}
