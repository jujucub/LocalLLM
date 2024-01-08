//
//  LLMBase.swift
//  Created by Guinmoon.

import Foundation
import llmfarm_core_cpp

public enum ModelLoadError: Error {
    // Throw when an invalid password is entered
    case modelLoadError

    // Throw when an expected resource is not found
    case contextLoadError
    
    case grammarLoadError

//        // Throw in all other cases
//        case unexpected(code: Int)
}


//func bridge(_ obj : T) -> UnsafeMutableRawPointer {
//    return UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
//}
//
//func bridge(_ ptr : UnsafeMutableRawPointer) -> T? {
//    return Unmanaged.fromOpaque(ptr).takeUnretainedValue()
//}

//func bridge<T : AnyObject>(obj : T) -> UnsafeRawPointer {
//    return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
//}
//
//func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
//    return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
//}



public class LLMBase {
    
    public var context: OpaquePointer?
    public var grammar: OpaquePointer?
    public var contextParams: ModelAndContextParams
    public var sampleParams: ModelSampleParams = .default    
    public var core_resourses = get_core_bundle_path()    
    public var session_tokens: [Int32] = []

    
    // Used to keep old context until it needs to be rotated or purge out for new tokens
    var past: [[ModelToken]] = [] // Will house both queries and responses in order
    //var n_history: Int32 = 0
    var nPast: Int32 = 0
    
    
    
    public  init(path: String, contextParams: ModelAndContextParams = .default) throws {                                
        self.contextParams = contextParams
        //        var params = gptneox_context_default_params()
        var params = gpt_context_default_params()
        params.n_ctx = contextParams.context
        params.n_parts = contextParams.parts
        params.seed = 0
        params.f16_kv = contextParams.f16Kv
        params.logits_all = contextParams.logitsAll
        params.vocab_only = contextParams.vocabOnly
        params.use_mlock = contextParams.useMlock
        params.embedding = contextParams.embedding
        // Check if model file exists
        if !FileManager.default.fileExists(atPath: path) {
            throw ModelError.modelNotFound(path)
        }
        // Load model at path
        //        self.context = gptneox_init_from_file(path, params)
        //        let test = test_fn()
        var load_res:Bool? = false
        do{
            try ExceptionCather.catchException {
                load_res = try? self.llm_load_model(path:path,contextParams:contextParams,params: params)
            }
        
            if load_res != true{
                throw ModelLoadError.modelLoadError
            }
            
            print("%s: seed = %d\n", params.seed);
            
            if contextParams.grammar_path != nil && contextParams.grammar_path! != ""{
                try? self.load_grammar(contextParams.grammar_path!)
            }
            
            print(String(cString: print_system_info()))
            try ExceptionCather.catchException {
                _ = try? self.llm_init_logits()
            }
    //        if exception != nil{
    //            throw ModelError.failedToEval
    //        }
            print("Logits inited.")
        }catch {
            print(error)
            throw error
        }
    }
    
    func TestMethod(){
        
        }
    
    deinit {
        
    }
    
    public func load_grammar(_ path:String) throws -> Void{
        do{
            try ExceptionCather.catchException {
                self.grammar = llama_load_grammar(path)
            }
        }
        catch {
            print(error)
            throw error
        }
    }
    
    public  func llm_load_model(path: String = "", contextParams: ModelAndContextParams = .default, params:gpt_context_params ) throws -> Bool{
        return false
    }
    
    
    public func llm_token_nl() -> ModelToken{
        return 13
    }
    
    public func llm_token_bos() -> ModelToken{
        return gpt_base_token_bos()
    }
    
    public func llm_token_eos() -> ModelToken{
        return gpt_base_token_eos()
    }
    
    func llm_n_vocab(_ ctx: OpaquePointer!) -> Int32{
        return gpt_base_n_vocab(ctx)
    }
    
    func llm_get_logits(_ ctx: OpaquePointer!) -> UnsafeMutablePointer<Float>?{
        return gpt_base_get_logits(ctx);
    }
    
    func llm_get_n_ctx(ctx: OpaquePointer!) -> Int32{
        return gpt_base_n_ctx(ctx)
    }
    
    
    // Simple topK, topP, temp sampling, with repeat penalty
    func llm_sample(ctx: OpaquePointer!,
                last_n_tokens: inout [ModelToken],
                temp: Float32,
                top_k: Int32,
                top_p: Float32,
                tfs_z: Float32,
                typical_p: Float32,
                repeat_last_n: Int32,
                repeat_penalty: Float32,
                alpha_presence: Float32,
                alpha_frequency: Float32,
                mirostat: Int32,
                mirostat_tau: Float32,
                mirostat_eta: Float32,
                penalize_nl: Bool) -> ModelToken {
        // Model input context size
        let n_ctx = llm_get_n_ctx(ctx: ctx)
        // Auto params
        
        let top_k = top_k <= 0 ? llm_n_vocab(ctx) : top_k
        let repeat_last_n = repeat_last_n < 0 ? n_ctx : repeat_last_n
        
        //
        let vocabSize = llm_n_vocab(ctx)
        guard let logits = llm_get_logits(ctx) else {
            print("GPT sample error logits nil")
            return 0
        }
        var candidates = Array<llama_dadbed9_token_data>()
        for i in 0 ..< vocabSize {
            candidates.append(llama_dadbed9_token_data(id: i, logit: logits[Int(i)], p: 0.0))
        }
        var candidates_p = llama_dadbed9_token_data_array(data: candidates.mutPtr, size: candidates.count, sorted: false)
        
        // Apply penalties
        let nl_token = Int(llm_token_nl())
        let nl_logit = logits[nl_token]
        let last_n_repeat = min(min(Int32(last_n_tokens.count), repeat_last_n), n_ctx)
        
        llama_dadbed9_sample_repetition_penalty(&candidates_p,
                    last_n_tokens.mutPtr.advanced(by: last_n_tokens.count - Int(repeat_last_n)),
                    Int(repeat_last_n), repeat_penalty)
        llama_dadbed9_sample_frequency_and_presence_penalties(ctx, &candidates_p,
                    last_n_tokens.mutPtr.advanced(by: last_n_tokens.count - Int(repeat_last_n)),
                    Int(last_n_repeat), alpha_frequency, alpha_presence)
        if(!penalize_nl) {
            logits[nl_token] = nl_logit
        }
        
        if (self.grammar != nil ) {
//            llama_sample_grammar(ctx,&candidates_p, self.grammar)
             llama_sample_grammar_for_dadbed9(ctx,&candidates_p, self.grammar)
        }
        
        var res_token:Int32 = 0
        
        if(temp <= 0) {
            // Greedy sampling
            res_token = llama_dadbed9_sample_token_greedy(ctx, &candidates_p)
        } else {
            var class_name = String(describing: self)
            if(mirostat == 1) {
                var mirostat_mu: Float = 2.0 * mirostat_tau
                let mirostat_m = 100
                llama_dadbed9_sample_temperature(ctx, &candidates_p, temp)
                if class_name != "llmfarm_core.LLaMa"{
                    res_token =  llama_dadbed9_sample_token_mirostat(ctx, &candidates_p, mirostat_tau, mirostat_eta, Int32(mirostat_m), &mirostat_mu, vocabSize);
                }else{
                    res_token =  llama_sample_token_mirostat_for_dadbed9(ctx, &candidates_p, mirostat_tau, mirostat_eta, Int32(mirostat_m), &mirostat_mu);
                }
            } else if(mirostat == 2) {
                var mirostat_mu: Float = 2.0 * mirostat_tau
                llama_dadbed9_sample_temperature(ctx, &candidates_p, temp)
                if class_name != "llmfarm_core.LLaMa"{
                    res_token =  llama_dadbed9_sample_token_mirostat_v2(ctx, &candidates_p, mirostat_tau, mirostat_eta, &mirostat_mu)
                }
                else{
                    res_token =  llama_sample_token_mirostat_v2_for_dadbed9(ctx, &candidates_p, mirostat_tau, mirostat_eta, &mirostat_mu)
                }
            } else {
                // Temperature sampling
                llama_dadbed9_sample_top_k(ctx, &candidates_p, top_k, 1)
                llama_dadbed9_sample_tail_free(ctx, &candidates_p, tfs_z, 1)
                llama_dadbed9_sample_typical(ctx, &candidates_p, typical_p, 1)
                llama_dadbed9_sample_top_p(ctx, &candidates_p, top_p, 1)
                llama_dadbed9_sample_temperature(ctx, &candidates_p, temp)
                if class_name != "llmfarm_core.LLaMa"{
                    res_token = llama_dadbed9_sample_token(ctx, &candidates_p)
                }else{
                    res_token = llama_sample_token_for_dadbed9(ctx, &candidates_p)
                }
            }
        }
        
        if (self.grammar != nil) {
            llama_grammar_accept_token(ctx, self.grammar, res_token);
        }
        return res_token

    }
    
    
    public func llm_eval(inputBatch:[ModelToken]) throws -> Bool{
        return false
    }
    
    func llm_init_logits() throws -> Bool {
        do{
            let inputs = [llm_token_bos(),llm_token_eos()]
            try ExceptionCather.catchException {
                _ = try? llm_eval(inputBatch: inputs)
            }
            return true
        }
        catch{
            print(error)
            throw error
        }
    }
    
//    public func llm_init_logits() throws -> Bool {
//        do{
//            if self.contextParams.warm_prompt.count<1{
//                self.contextParams.warm_prompt = "\n\n\n"
//            }
//            let inputs = llm_tokenize(self.contextParams.warm_prompt)
//            if try llm_eval(inputBatch: inputs) == false {
//                throw ModelError.failedToEval
//            }
//            return true
//        }
//        catch{
//            print(error)
//        }
//        return false
//    }
    
    public func llm_token_to_str(outputToken:Int32) -> String? {
        if let cStr = gpt_base_token_to_str(context, outputToken){
            return String(cString: cStr)
        }
        return nil
    }
    
    
    
    public func predict(_ input: String, _ callback: ((String, Double) -> Bool) ) throws -> String {
        let params = sampleParams
        let contextLength = Int32(contextParams.context)
        print("Past token count: \(nPast)/\(contextLength) (\(past.count))")
        // Tokenize with prompt format
        var inputTokens = tokenizePrompt(input, self.contextParams.promptFormat)
        if inputTokens.count == 0{
            return "Empty input."
        }
        self.session_tokens.append(contentsOf: inputTokens)
        let inputTokensCount = inputTokens.count
        print("Input tokens: \(inputTokens)")
        // Add new input tokens to past array
        past.append(inputTokens)
        // Create space in context if needed
        if inputTokensCount > contextLength {
            throw ModelError.inputTooLong
        }
//        var totalLength = nPast + Int32(inputTokensCount)
        // Input
        var inputBatch: [ModelToken] = []
        do {
            while inputTokens.count > 0 {
                inputBatch.removeAll()
                // See how many to eval (up to batch size??? or can we feed the entire input)
                // Move tokens to batch
                let evalCount = min(inputTokens.count, Int(params.n_batch))
                inputBatch.append(contentsOf: inputTokens[0 ..< evalCount])
                
                inputTokens.removeFirst(evalCount)
                if self.nPast + Int32(inputBatch.count) >= self.contextParams.context{
                    self.nPast = 0
                    try ExceptionCather.catchException {
                        _ = try? self.llm_eval(inputBatch: [self.llm_token_eos()])
                    }
//                    throw ModelError.contextLimit
                }
                var eval_res:Bool? = nil
                try ExceptionCather.catchException {
                    eval_res = try? self.llm_eval(inputBatch: inputBatch)
                }
                if eval_res == false{
                    throw ModelError.failedToEval
                }
                nPast += Int32(evalCount)
            }
            // Output
            var outputRepeatTokens: [ModelToken] = []
            var outputTokens: [ModelToken] = []
            var output = [String]()
            // Loop until target count is reached
            var outputEnabled = true
            while outputEnabled {
                // Pull a generation from context
                var outputToken:Int32 = -1
                try ExceptionCather.catchException {
                    outputToken = self.llm_sample(
                        ctx: self.context,
                        last_n_tokens: &outputRepeatTokens,
                        temp: params.temp,
                        top_k: params.top_k,
                        top_p: params.top_p,
                        tfs_z: params.tfs_z,
                        typical_p: params.typical_p,
                        repeat_last_n: params.repeat_last_n,
                        repeat_penalty: params.repeat_penalty,
                        alpha_presence: params.presence_penalty,
                        alpha_frequency: params.frequence_penalty,
                        mirostat: params.mirostat,
                        mirostat_tau: params.mirostat_tau,
                        mirostat_eta: params.mirostat_eta,
                        penalize_nl: params.penalize_nl
                    )
                }
                // Add output token to array
                outputTokens.append(outputToken)
                // Repeat tokens update
                outputRepeatTokens.append(outputToken)
                if outputRepeatTokens.count > params.repeat_last_n {
                    outputRepeatTokens.removeFirst()
                }
                // Check for eos - end early - check eos before bos in case they are the same
                if outputToken == llm_token_eos() {
                    outputEnabled = false
                    print("[EOS]")
                    break
                }
                // Check for bos, skip callback if so, bos = eos for most gptneox so this should typically never occur
                var skipCallback = false
                if outputToken == llm_token_bos()  {
                    print("[BOS]")
                    skipCallback = true
                }
                // Convert token to string and callback
                self.session_tokens.append(outputToken)
                if !skipCallback, let str = llm_token_to_str(outputToken: outputToken){
                    output.append(str)
                    // Per token callback
                    let (output, time) = Utils.time {
                        return str
                    }
                    if callback(output, time) {
                        // Early exit if requested by callback
                        print(" * exit requested by callback *")
                        //generating = false
                        outputEnabled = false //outputRemaining = 0
                        break
                    }
                }
                // Check if we need to run another response eval
                if outputEnabled {
                    // Send generated token back into model for next generation
                    var eval_res:Bool? = nil
                    if self.nPast >= self.contextParams.context - 4{
                        self.nPast = self.nPast / 2
                        outputToken = self.llm_token_eos()
                        try ExceptionCather.catchException {
                            _ = try? self.llm_eval(inputBatch: [outputToken])
                        }
                        print("Context Limit!")
//                        throw ModelError.contextLimit
                    }
                    try ExceptionCather.catchException {
                        eval_res = try? self.llm_eval(inputBatch: [outputToken])
                    }
                    if eval_res == false{
                        print("Eval res false")
                        throw ModelError.failedToEval
                    }
                    // Increment past count
                    nPast += 1
                }
            }
            // Update past with most recent response
            past.append(outputTokens)
            print("Total tokens: \(inputTokensCount + outputTokens.count) (\(inputTokensCount) -> \(outputTokens.count))")
            print("Past token count: \(nPast)/\(contextLength) (\(past.count))")
            // Return full string for case without callback
            return output.joined()
        }catch{
            print(error)
            throw error
        }
    }
    
//    public func embeddings(_ input: String) throws -> [Float] {
//        // Tokenize the prompt
//        let inputs = llm_tokenize(input)
//        
//        guard inputs.count > 0 else {
//            return []
//        }
//        
//        _ = try llm_eval(inputBatch: inputs)
//        
//        let embeddingsCount = Int(gpt_base_n_embd(context))
//        guard let embeddings = gpt_base_get_embeddings(context) else {
//            return []
//        }
//        return Array(UnsafeBufferPointer(start: embeddings, count: embeddingsCount))
//    }
    
    public func llm_tokenize(_ input: String) -> [ModelToken] {
        if input.count == 0 {
            return []
        }
        
        var embeddings = Array<ModelToken>(repeating: gpt_token(), count: input.utf8.count)
        let n = gpt_base_tokenize(context, input, &embeddings, Int32(input.utf8.count), self.contextParams.add_bos_token)
        if n<=0{
            return []
        }
        if Int(n) <= embeddings.count {
            embeddings.removeSubrange(Int(n)..<embeddings.count)
        }
        
        if self.contextParams.add_eos_token {
            embeddings.append(gpt_base_token_eos())
        }
        
        return embeddings
    }
    
    public func tokenizePrompt(_ input: String, _ style: ModelPromptStyle) -> [ModelToken] {
        switch style {
        case .None:
            return llm_tokenize(input)
        case .Custom:
            var formated_input = self.contextParams.custom_prompt_format.replacingOccurrences(of: "{{prompt}}", with: input)
            formated_input = formated_input.replacingOccurrences(of: "\\n", with: "\n")
            return llm_tokenize(formated_input)
        // case .ChatBase:
        //     return llm_tokenize("<human>: " + input + "\n<bot>:")
        // case .OpenAssistant:
        //     let inputTokens = llm_tokenize("<|prompter|>" + input + "<|endoftext|>" + "<|assistant|>")
        //     return inputTokens
        // case .RedPajama_chat:
        //     return llm_tokenize("<human>:\n" + input + "\n<bot>:")
        // case .Dolly_b3:
        //     let  INSTRUCTION_KEY = "### Instruction:";
        //     let  RESPONSE_KEY    = "### Response:";
        //     let  INTRO_BLURB     = "Below is an instruction that describes a task. Write a response that appropriately completes the request.";
        //     let inputTokens = llm_tokenize(INTRO_BLURB + INSTRUCTION_KEY + input + RESPONSE_KEY)
        //     return inputTokens
        // case .StableLM_Tuned:
        //     let inputTokens = llm_tokenize("<|USER|>" + input + "<|ASSISTANT|>")
        //     return inputTokens
        // case .LLaMa:
        //     let input = " " + input
        //     return llm_tokenize(input, bos: true)
        // case .LLaMa_QA:
        //     let input = "Question: " + input + "\n\nAnswer: "
        //     return llm_tokenize(input, bos: true)
         }
    }
}


