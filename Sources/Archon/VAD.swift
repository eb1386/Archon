import Foundation
import onnxruntime_objc

class VAD {
    private var session: ORTSession?
    private var env: ORTEnv?
    let threshold: Float

    // recurrent state for silero
    private var hState: [Float]
    private var cState: [Float]
    private let sr: Int = 16000

    init(modelPath: String, threshold: Float = 0.5) {
        self.threshold = threshold
        // 2 layers, 1 batch, 64 hidden
        self.hState = [Float](repeating: 0, count: 128)
        self.cState = [Float](repeating: 0, count: 128)

        let resolved = Config.expandPath(modelPath)
        do {
            env = try ORTEnv(loggingLevel: .warning)
            let sessionOpts = try ORTSessionOptions()
            try sessionOpts.setLogSeverityLevel(.warning)
            session = try ORTSession(env: env!, modelPath: resolved, sessionOptions: sessionOpts)
        } catch {
            print("[!] vad setup failed: \(error)")
        }
    }

    func detect(samples: [Float]) -> Float {
        guard let session = session else { return 0 }

        do {
            let inData = Data(bytes: samples, count: samples.count * 4)
            let inTensor = try ORTValue(
                tensorData: NSMutableData(data: inData),
                elementType: .float,
                shape: [1, NSNumber(value: samples.count)]
            )

            var srVal = Int64(sr)
            let srData = Data(bytes: &srVal, count: 8)
            let srTensor = try ORTValue(
                tensorData: NSMutableData(data: srData),
                elementType: .int64, shape: [1]
            )

            let hData = Data(bytes: hState, count: hState.count * 4)
            let hTensor = try ORTValue(
                tensorData: NSMutableData(data: hData),
                elementType: .float, shape: [2, 1, 64]
            )

            let cData = Data(bytes: cState, count: cState.count * 4)
            let cTensor = try ORTValue(
                tensorData: NSMutableData(data: cData),
                elementType: .float, shape: [2, 1, 64]
            )

            let out = try session.run(
                withInputs: ["input": inTensor, "sr": srTensor, "h": hTensor, "c": cTensor],
                outputNames: ["output", "hn", "cn"],
                runOptions: nil
            )

            guard let outVal = out["output"] else { return 0 }
            let prob = (try outVal.tensorData() as Data).withUnsafeBytes { $0.load(as: Float.self) }

            if let hn = out["hn"] {
                hState = (try hn.tensorData() as Data).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            }
            if let cn = out["cn"] {
                cState = (try cn.tensorData() as Data).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            }

            return prob
        } catch {
            return 0
        }
    }

    func reset() {
        hState = [Float](repeating: 0, count: 128)
        cState = [Float](repeating: 0, count: 128)
    }
}
