import Foundation

/// Parsed printer state. Mirrors `ad4core.models.PrinterStatus`.
public struct PrinterStatus: Equatable, Sendable {
    public var raw: String
    public var machineStatus: String?
    public var moveMode: String?
    public var currentFile: String?
    public var nozzleCurrent: Int?
    public var nozzleTarget: Int?
    public var bedCurrent: Int?
    public var bedTarget: Int?
    public var sdCurrent: Int?
    public var sdTotal: Int?
    public var layerCurrent: Int?
    public var layerTotal: Int?

    public init(
        raw: String,
        machineStatus: String? = nil,
        moveMode: String? = nil,
        currentFile: String? = nil,
        nozzleCurrent: Int? = nil,
        nozzleTarget: Int? = nil,
        bedCurrent: Int? = nil,
        bedTarget: Int? = nil,
        sdCurrent: Int? = nil,
        sdTotal: Int? = nil,
        layerCurrent: Int? = nil,
        layerTotal: Int? = nil
    ) {
        self.raw = raw
        self.machineStatus = machineStatus
        self.moveMode = moveMode
        self.currentFile = currentFile
        self.nozzleCurrent = nozzleCurrent
        self.nozzleTarget = nozzleTarget
        self.bedCurrent = bedCurrent
        self.bedTarget = bedTarget
        self.sdCurrent = sdCurrent
        self.sdTotal = sdTotal
        self.layerCurrent = layerCurrent
        self.layerTotal = layerTotal
    }

    public var isPrinting: Bool {
        guard let status = machineStatus else { return false }
        return ["BUILDING_FROM_SD", "BUILDING", "PRINTING"].contains(status)
    }

    public var progressPercent: Double? {
        guard let total = sdTotal, total > 0, let current = sdCurrent else { return nil }
        return min(100.0, max(0.0, (Double(current) / Double(total)) * 100.0))
    }
}
