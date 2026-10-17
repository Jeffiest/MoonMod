#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <ranges>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <exception>

#include "moonmod/api.hpp"

namespace moonmod {

// A bounded, deterministic modifier registry shared by both game adapters. Native hit
// pipelines call Apply() only after their own defense, elemental, and damage-block rules.
class CombatDamageFormulaRegistry {
public:
    ApiCallResult Register(std::string_view owner, const Json &arguments) {
        if (!IsValidModId(owner) || !arguments.is_array() || arguments.size() != 1 ||
            !arguments[0].is_object()) {
            return Invalid("expected one formula object owned by the calling mod");
        }

        const Json &request = arguments[0];
        for (auto field = request.begin(); field != request.end(); ++field) {
            if (field.key() != "id" && field.key() != "operation" && field.key() != "value" &&
                field.key() != "priority") {
                return Invalid("formula contains an unsupported field");
            }
        }
        if (!request.contains("id") || !request["id"].is_string() ||
            !request.contains("operation") || !request["operation"].is_string() ||
            !request.contains("value") || !request["value"].is_number() ||
            (request.contains("priority") && !request["priority"].is_number_integer())) {
            return Invalid("expected {id, operation = add|multiply|set, value, priority = optional integer}");
        }

        const std::string local_id = request["id"].get<std::string>();
        if (local_id.empty() || local_id.size() > 64 || local_id.find(':') != std::string::npos ||
            !std::all_of(local_id.begin(), local_id.end(), [](unsigned char character) {
                return (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') ||
                       (character >= '0' && character <= '9') || character == '.' || character == '_' ||
                       character == '-';
            })) {
            return Invalid("formula id must be a local identifier of 1-64 ASCII letters, digits, '.', '_' or '-'");
        }

        Formula formula;
        formula.owner = std::string(owner);
        formula.id = local_id;
        formula.operation = request["operation"].get<std::string>();
        try {
            formula.value = request["value"].get<double>();
        } catch (const std::exception &) {
            return Invalid("formula value is outside the numeric range");
        }
        if (request.contains("priority")) {
            try {
                const std::int64_t priority = request["priority"].get<std::int64_t>();
                if (priority < -1000 || priority > 1000) return Invalid("priority must be in [-1000, 1000]");
                formula.priority = static_cast<int>(priority);
            } catch (const std::exception &) {
                return Invalid("priority is outside the integer range");
            }
        }
        if (!std::isfinite(formula.value)) return Invalid("formula value must be finite");
        if (formula.operation == "add") {
            if (formula.value < -1000000.0 || formula.value > 1000000.0) {
                return Invalid("add value must be in [-1000000, 1000000]");
            }
        } else if (formula.operation == "multiply") {
            if (formula.value < 0.0 || formula.value > 100.0) {
                return Invalid("multiply value must be in [0, 100]");
            }
        } else if (formula.operation == "set") {
            if (formula.value < 0.0 || formula.value > 1000000.0) {
                return Invalid("set value must be in [0, 1000000]");
            }
        } else {
            return Invalid("operation must be 'add', 'multiply', or 'set'");
        }

        const auto existing = std::ranges::find_if(formulas_, [&formula](const auto &entry) {
            return entry.second.owner == formula.owner && entry.second.id == formula.id;
        });
        if (existing != formulas_.end()) {
            if (existing->second.SameDefinition(formula)) {
                return {ApiCallStatus::Ok,
                        {{"id", formula.owner + ":" + formula.id}, {"operation", formula.operation},
                         {"value", formula.value}, {"priority", formula.priority}, {"idempotent", true}}, {}};
            }
            existing->second = formula;
            return {ApiCallStatus::Ok,
                    {{"id", formula.owner + ":" + formula.id}, {"operation", formula.operation},
                     {"value", formula.value}, {"priority", formula.priority}, {"idempotent", false}}, {}};
        }

        const std::size_t owner_count = std::ranges::count_if(formulas_, [&formula](const auto &entry) {
            return entry.second.owner == formula.owner;
        });
        if (owner_count >= 64 || formulas_.size() >= 512) {
            return Invalid(owner_count >= 64 ? "a mod may register at most 64 combat formulas"
                                             : "the game supports at most 512 combat formulas");
        }

        const auto key = std::make_tuple(formula.priority, formula.owner, formula.id);
        formulas_.emplace(key, formula);
        return {ApiCallStatus::Ok,
                {{"id", formula.owner + ":" + formula.id}, {"operation", formula.operation},
                 {"value", formula.value}, {"priority", formula.priority}, {"idempotent", false}}, {}};
    }

    float Apply(float damage) const {
        if (!std::isfinite(damage) || damage <= 0.0f) return 0.0f;
        double result = std::min<double>(damage, 1000000.0);
        for (const auto &[key, formula] : formulas_) {
            (void)key;
            if (formula.operation == "add") result += formula.value;
            else if (formula.operation == "multiply") result *= formula.value;
            else result = formula.value;
            if (!std::isfinite(result) || result <= 0.0) return 0.0f;
            result = std::min(result, 1000000.0);
        }
        return static_cast<float>(result);
    }

    void RemoveOwner(std::string_view owner) {
        std::erase_if(formulas_, [owner](const auto &entry) { return entry.second.owner == owner; });
    }

    void Clear() { formulas_.clear(); }

private:
    struct Formula {
        std::string owner;
        std::string id;
        std::string operation;
        double value = 0.0;
        int priority = 0;

        bool SameDefinition(const Formula &other) const {
            return owner == other.owner && id == other.id && operation == other.operation &&
                   value == other.value && priority == other.priority;
        }
    };

    static ApiCallResult Invalid(std::string message) {
        return {ApiCallStatus::InvalidArgument, nullptr, std::move(message)};
    }

    static bool IsValidModId(std::string_view id) {
        if (id.empty() || id.size() > 64) return false;
        return std::all_of(id.begin(), id.end(), [](unsigned char character) {
            return (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') ||
                   character == '.' || character == '_' || character == '-';
        });
    }

    std::map<std::tuple<int, std::string, std::string>, Formula> formulas_;
};

inline float ApplyCombatDamageBonuses(float damage, const Json &bonuses) {
    if (!std::isfinite(damage) || damage <= 0.0f) return 0.0f;
    double result = std::min<double>(damage, 1000000.0);
    if (!bonuses.is_array()) return static_cast<float>(result);
    for (const Json &bonus : bonuses) {
        if (!bonus.is_object() || !bonus.contains("rank") || !bonus["rank"].is_number_integer() ||
            !bonus.contains("per_rank") || !bonus["per_rank"].is_number()) {
            continue;
        }
        const std::int64_t rank = bonus["rank"].get<std::int64_t>();
        const double per_rank = bonus["per_rank"].get<double>();
        if (rank <= 0 || rank > 99 || !std::isfinite(per_rank) || per_rank <= 0.0 || per_rank > 1.0) continue;
        result *= 1.0 + per_rank * static_cast<double>(rank);
        if (!std::isfinite(result) || result >= 1000000.0) {
            result = 1000000.0;
            break;
        }
    }
    return static_cast<float>(result);
}

} // namespace moonmod

