#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "moonmod/runtime.hpp"

namespace moonmod {

inline constexpr int kManagerVisibleMods = 7;
inline constexpr int kManagerVisibleSettings = 5;
inline constexpr int kManagerVisibleQuestObjectives = 4;
inline constexpr int kManagerVisibleJournalObjectives = 4;
inline constexpr int kManagerVisibleSkills = 4;

struct ManagerUiAction {
    std::string id;
    std::string owner_id;
    std::string label;
    std::string description;
};

struct ManagerJournalQuest {
    std::string mod_id;
    std::string mod_name;
    Json        quest;
};

struct ManagerUiState {
    bool        open = false;
    bool        settings_focus = false;
    bool        native_trust_focus = false;
    bool        native_trust_confirmation = false;
    bool        pending_native_trust = false;
    int         detail_tab = 0;
    int         selected_mod = 0;
    int         first_mod = 0;
    int         selected_setting = 0;
    int         first_setting = 0;
    int         selected_action = 0;
    int         first_action = 0;
    int         selected_quest = 0;
    int         first_quest_objective = 0;
    int         selected_skill = 0;
    int         first_skill = 0;
    int         selected_journal_quest = 0;
    int         first_journal_quest = 0;
    std::string notice;
    int         notice_frames = 0;
};

struct ManagerInput {
    bool up = false;
    bool down = false;
    bool left = false;
    bool right = false;
    bool confirm = false;
    bool cancel = false;
    bool next_focus = false;
    bool previous_focus = false;
    bool mouse_left = false;
    bool mouse_right = false;
    float mouse_x = -1.0f;
    float mouse_y = -1.0f;
    float wheel = 0.0f;
};

ManagerUiState &ManagerState();
void           OpenManager();
void           CloseManager();
bool           ManagerOpen();
void           ShowManagerNotice(std::string message, int duration_frames);
void           AdvanceManagerUi();
bool           HandleManagerInput(const ManagerInput &input);
const ModRecord *ManagerSelectedMod();
bool RegisterManagerAction(std::string_view owner_id, std::string_view local_id, std::string label,
                           std::string description, std::string &error);
bool RemoveManagerAction(std::string_view owner_id, std::string_view local_id);
void RemoveManagerActions(std::string_view owner_id);
std::vector<ManagerUiAction> ManagerActions(std::string_view owner_id);
ApiCallResult ManagerQuests(std::string_view owner_id);
std::vector<ManagerJournalQuest> ManagerJournalQuests();
std::string ManagerQuestRewardSummary(const Json &quest);
ApiCallResult ManagerSkills(std::string_view owner_id);
bool ActivateManagerAction(std::string_view owner_id, std::string_view local_id);

} // namespace moonmod
