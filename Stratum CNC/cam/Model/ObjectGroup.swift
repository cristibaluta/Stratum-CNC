//
//  ObjectGroup.swift
//  Stratum CNC
//
//  A group is a virtual object: a named set of project objects that can be given setups as one.
//  It stores only ids, so the members keep their own placement, and an object can be in several
//  groups. A setup made for a group (`Setup.groupID`) includes the group's members; when the
//  members change the setup follows (`CAMModel.syncGroupSetups`), keeping the positions set in it.
//

import Foundation

struct ObjectGroup: Identifiable, Codable, Hashable, Sendable {

    var id = UUID()
    var name: String
    /// The objects of the group, in the order they were added
    var memberIDs: [UUID]
}

extension CAMModel {

    /// Groups the given objects (two or more, each once) under a new name. Returns the group's id.
    @discardableResult
    func createGroup(name: String? = nil, memberIDs: [UUID]) -> UUID? {
        var seen = Set<UUID>()
        let members = memberIDs.filter { seen.insert($0).inserted }
        guard members.count >= 2 else {
            return nil
        }
        let taken = Set(objectGroups.map(\.name))
        var title = name?.trimmed ?? ""
        if title.isEmpty {
            title = "Group"
            var n = 2
            while taken.contains(title) {
                title = "Group \(n)"
                n += 1
            }
        }
        let group = ObjectGroup(name: title, memberIDs: members)
        objectGroups.append(group)
        return group.id
    }

    func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty, let index = objectGroups.firstIndex(where: { $0.id == id }),
              objectGroups[index].name != trimmed else {
            return
        }
        objectGroups[index].name = trimmed
    }

    /// Replaces the members of a group. A group left empty is removed.
    func setGroupMembers(_ id: UUID, to memberIDs: [UUID]) {
        guard let index = objectGroups.firstIndex(where: { $0.id == id }) else {
            return
        }
        var seen = Set<UUID>()
        let members = memberIDs.filter { seen.insert($0).inserted }
        guard !members.isEmpty else {
            deleteGroup(id)
            return
        }
        guard objectGroups[index].memberIDs != members else {
            return
        }
        objectGroups[index].memberIDs = members
        syncGroupSetups(id)
    }

    /// Dissolves a group. Its setups stay, with the objects they include now, as plain setups.
    func deleteGroup(_ id: UUID) {
        guard objectGroups.contains(where: { $0.id == id }) else {
            return
        }
        for setup in setups where setup.groupID == id {
            setSetupGroup(setup.id, to: nil)
        }
        objectGroups.removeAll { $0.id == id }
    }

    /// A new setup on a face for all the members of a group.
    @discardableResult
    func addGroupSetup(_ groupID: UUID, face: SetupFace, axis: SetupAxis? = nil) -> UUID? {
        guard let group = objectGroups.first(where: { $0.id == groupID }) else {
            return nil
        }
        let id = addSetup(face: face, axis: axis, inheritingFixtures: true)
        setSetupObjects(id, to: group.memberIDs)
        setSetupGroup(id, to: groupID)
        return id
    }

    /// Makes the items of the group's setups match the group's members.
    func syncGroupSetups(_ groupID: UUID) {
        guard let group = objectGroups.first(where: { $0.id == groupID }) else {
            return
        }
        for setup in setups where setup.groupID == groupID {
            setSetupObjects(setup.id, to: group.memberIDs)
        }
    }

    /// Drops members that no longer exist (an object was deleted), and the groups left empty.
    /// Waits until every STEP body has loaded, so one still loading isn't taken for a missing one.
    func pruneGroups(existing ids: Set<UUID>) {
        guard !objectGroups.isEmpty,
              stepWorkspace.modelEntries.allSatisfy({ $0.body != nil }) else {
            return
        }
        for group in objectGroups {
            let members = group.memberIDs.filter { ids.contains($0) }
            if members.count != group.memberIDs.count {
                setGroupMembers(group.id, to: members)
            }
        }
    }

    /// The groups an object is a member of.
    func groups(containing objectID: UUID) -> [ObjectGroup] {
        objectGroups.filter { $0.memberIDs.contains(objectID) }
    }
}
