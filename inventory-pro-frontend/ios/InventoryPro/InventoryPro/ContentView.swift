import SwiftUI
import AVFoundation
import Combine

/// MARK: - Models
struct User: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let role: String
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, email, name, role
        case createdAt = "created_at"
    }
}

struct Company: Codable {
    let id: String
    let name: String
    let code: String
    let subscriptionTier: String
    let maxUsers: Int?
    var lowStockThreshold: Int? // New field for admin-configurable low stock threshold
    
    enum CodingKeys: String, CodingKey {
        case id, name, code
        case subscriptionTier = "subscription_tier"
        case maxUsers = "max_users"
        case lowStockThreshold = "low_stock_threshold"
    }
}

struct Item: Codable, Identifiable {
    let id: String
    let name: String
    var quantity: Int
    let barcode: String
    let updatedAt: String?
    var lowStockThreshold: Int? // Item-specific low stock threshold
    
    enum CodingKeys: String, CodingKey {
        case id, name, quantity, barcode
        case updatedAt = "updated_at"
        case lowStockThreshold = "low_stock_threshold"
    }
}

struct Activity: Codable, Identifiable {
    let id: String
    let itemName: String
    let type: String
    let quantity: Int?
    let oldQuantity: Int?
    let userName: String?
    let createdAt: String?
    let sessionTitle: String? // New field for batch operation titles
    let itemId: String? // New field to link activities to specific items
    
    enum CodingKeys: String, CodingKey {
        case id, type, quantity
        case itemName = "item_name"
        case oldQuantity = "old_quantity"
        case userName = "user_name"
        case createdAt = "created_at"
        case sessionTitle = "session_title"
        case itemId = "item_id"
    }
}

struct InviteLink: Codable {
    let token: String
    let companyName: String
    let inviterName: String
    let role: String
    let expiresAt: String
    
    enum CodingKeys: String, CodingKey {
        case token
        case companyName = "company_name"
        case inviterName = "inviter_name"
        case role
        case expiresAt = "expires_at"
    }
}

// Response structure for invite links
struct InviteLinkResponse: Decodable {
    let token: String
    let companyName: String
    let inviterName: String
    let role: String
    let expiresAt: String
    let inviteUrl: String
    
    enum CodingKeys: String, CodingKey {
        case token
        case companyName = "company_name"
        case inviterName = "inviter_name"
        case role
        case expiresAt = "expires_at"
        case inviteUrl = "invite_url"
    }
}

/// MARK: - API Service
@MainActor
class APIService: ObservableObject {
    static let shared = APIService()
    private let baseURL = "https://shimmering-perfection-production.up.railway.app"
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var currentCompany: Company?
    
    private init() {
        checkAuthStatus()
    }
    
    private func checkAuthStatus() {
        if let token = UserDefaults.standard.string(forKey: "authToken"),
           let userData = UserDefaults.standard.data(forKey: "currentUser"),
           let user = try? JSONDecoder().decode(User.self, from: userData) {
            
            self.currentUser = user
            
            // Also load company data if available
            if let companyData = UserDefaults.standard.data(forKey: "currentCompany"),
               let company = try? JSONDecoder().decode(Company.self, from: companyData) {
                self.currentCompany = company
            }
            
            self.isAuthenticated = true
            print("✅ Auth status restored - User: \(user.name), Company: \(currentCompany?.name ?? "None")")
        } else {
            print("❌ No valid auth data found")
            self.isAuthenticated = false
        }
    }
    
    private func makeRequest<T: Decodable>(endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw URLError(.badURL)
        }
        
        print("🔵 Request URL: \(url)")
        print("🔵 Method: \(method)")
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
            print("📤 Request body: \(String(data: body, encoding: .utf8) ?? "nil")")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Log the raw response
        print("📥 Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        print("📥 Status code: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 401 {
            DispatchQueue.main.async {
                self.logout()
            }
            throw URLError(.userAuthenticationRequired)
        }
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorData["error"] {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            throw URLError(.badServerResponse)
        }
        
        // Try to decode the response
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ Decoding error: \(error)")
            print("❌ Failed to decode type: \(T.self)")
            throw error
        }
    }
    
    func login(email: String, password: String) async throws {
        struct LoginRequest: Encodable {
            let email: String
            let password: String
        }
        
        struct LoginResponse: Decodable {
            let success: Bool
            let user: User
            let company: Company
            let token: String
        }
        
        print("🔐 Starting login for: \(email)")
        
        let body = try JSONEncoder().encode(LoginRequest(email: email, password: password))
        
        do {
            let response: LoginResponse = try await makeRequest(endpoint: "/api/auth/login", method: "POST", body: body)
            
            print("✅ Login successful for: \(response.user.name)")
            
            UserDefaults.standard.set(response.token, forKey: "authToken")
            if let userData = try? JSONEncoder().encode(response.user) {
                UserDefaults.standard.set(userData, forKey: "currentUser")
            }
            if let companyData = try? JSONEncoder().encode(response.company) {
                UserDefaults.standard.set(companyData, forKey: "currentCompany")
            }
            
            self.currentUser = response.user
            self.currentCompany = response.company
            self.isAuthenticated = true
            
        } catch let urlError as URLError {
            print("❌ Network error during login: \(urlError.localizedDescription)")
            print("❌ URL Error code: \(urlError.code.rawValue)")
            
            if urlError.code == .notConnectedToInternet {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "No internet connection"])
            } else if urlError.code == .timedOut {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Request timed out - server may be slow"])
            } else if urlError.code == .cannotConnectToHost {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to server"])
            } else {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Network error: \(urlError.localizedDescription)"])
            }
            
        } catch let decodingError as DecodingError {
            print("❌ Decoding error details: \(decodingError)")
            print("❌ Decoding error description: \(decodingError.localizedDescription)")
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Server response format error"])
            
        } catch let nsError as NSError {
            print("❌ NSError during login: \(nsError.localizedDescription)")
            print("❌ NSError code: \(nsError.code)")
            print("❌ NSError domain: \(nsError.domain)")
            throw nsError
            
        } catch {
            print("❌ Unknown error during login: \(error)")
            print("❌ Error type: \(type(of: error))")
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Login failed: \(error.localizedDescription)"])
        }
    }
    
    func registerCompany(companyName: String, adminEmail: String, adminPassword: String, adminName: String) async throws {
        struct RegisterRequest: Encodable {
            let companyName: String
            let adminEmail: String
            let adminPassword: String
            let adminName: String
        }
        
        struct RegisterResponse: Decodable {
            let success: Bool
            let user: User
            let company: Company
            let token: String
        }
        
        let body = try JSONEncoder().encode(RegisterRequest(companyName: companyName, adminEmail: adminEmail, adminPassword: adminPassword, adminName: adminName))
        let response: RegisterResponse = try await makeRequest(endpoint: "/api/companies/register", method: "POST", body: body)
        
        UserDefaults.standard.set(response.token, forKey: "authToken")
        if let userData = try? JSONEncoder().encode(response.user) {
            UserDefaults.standard.set(userData, forKey: "currentUser")
        }
        if let companyData = try? JSONEncoder().encode(response.company) {
            UserDefaults.standard.set(companyData, forKey: "currentCompany")
        }
        
        self.currentUser = response.user
        self.currentCompany = response.company
        self.isAuthenticated = true
    }
    
    func logout() {
        print("🚪 Logging out...")
        
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "currentUser")
        UserDefaults.standard.removeObject(forKey: "currentCompany")
        
        // Force synchronize
        UserDefaults.standard.synchronize()
        
        currentUser = nil
        currentCompany = nil
        isAuthenticated = false
        
        print("🚪 Logout complete. isAuthenticated: \(isAuthenticated)")
    }
    
    // MARK: - Items
    func getItems() async throws -> [Item] {
        return try await makeRequest(endpoint: "/api/items")
    }
    
    func createItem(name: String, quantity: Int, barcode: String) async throws -> Item {
        struct CreateItemRequest: Encodable {
            let name: String
            let quantity: Int
            let barcode: String
        }
        
        let body = try JSONEncoder().encode(CreateItemRequest(name: name, quantity: quantity, barcode: barcode))
        return try await makeRequest(endpoint: "/api/items", method: "POST", body: body)
    }
    
    func updateItem(id: String, quantity: Int) async throws -> Item {
        struct UpdateItemRequest: Encodable {
            let id: String
            let quantity: Int
        }
        
        let body = try JSONEncoder().encode(UpdateItemRequest(id: id, quantity: quantity))
        return try await makeRequest(endpoint: "/api/items", method: "PUT", body: body)
    }
    
    func updateItemLowStockThreshold(id: String, threshold: Int) async throws -> Item {
        struct UpdateThresholdRequest: Encodable {
            let id: String
            let lowStockThreshold: Int
        }
        
        let body = try JSONEncoder().encode(UpdateThresholdRequest(id: id, lowStockThreshold: threshold))
        return try await makeRequest(endpoint: "/api/items/threshold", method: "PUT", body: body)
    }
    
    func deleteItem(id: String) async throws {
        struct DeleteItemRequest: Encodable {
            let id: String
        }
        
        let body = try JSONEncoder().encode(DeleteItemRequest(id: id))
        let _: [String: Bool] = try await makeRequest(endpoint: "/api/items", method: "DELETE", body: body)
    }
    
    func findItemByBarcode(_ barcode: String) async throws -> Item? {
        do {
            let item: Item = try await makeRequest(endpoint: "/api/items/search?barcode=\(barcode)")
            return item
        } catch {
            return nil
        }
    }
    
    // MARK: - Activities
    func getActivities() async throws -> [Activity] {
        return try await makeRequest(endpoint: "/api/activities")
    }
    
    func getItemActivities(itemId: String) async throws -> [Activity] {
        return try await makeRequest(endpoint: "/api/activities/item/\(itemId)")
    }
    
    func createBatchActivity(sessionTitle: String, items: [(itemId: String, quantityChange: Int)]) async throws {
        struct BatchActivityRequest: Encodable {
            let sessionTitle: String
            let items: [BatchItem]
            
            struct BatchItem: Encodable {
                let itemId: String
                let quantityChange: Int
            }
        }
        
        let batchItems = items.map { BatchActivityRequest.BatchItem(itemId: $0.itemId, quantityChange: $0.quantityChange) }
        let body = try JSONEncoder().encode(BatchActivityRequest(sessionTitle: sessionTitle, items: batchItems))
        let _: [String: Bool] = try await makeRequest(endpoint: "/api/activities/batch", method: "POST", body: body)
    }
    
    // MARK: - Company
    func getCompanyInfo() async throws -> Company {
        struct CompanyResponse: Decodable {
            let company: Company
        }
        let response: CompanyResponse = try await makeRequest(endpoint: "/api/companies/info")
        return response.company
    }
    
    func updateCompanyLowStockThreshold(_ threshold: Int) async throws -> Company {
        struct UpdateThresholdRequest: Encodable {
            let lowStockThreshold: Int
        }
        
        let body = try JSONEncoder().encode(UpdateThresholdRequest(lowStockThreshold: threshold))
        let response: Company = try await makeRequest(endpoint: "/api/companies/threshold", method: "PUT", body: body)
        
        // Update local company data
        if let companyData = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(companyData, forKey: "currentCompany")
        }
        self.currentCompany = response
        
        return response
    }
    
    // MARK: - Users
    func getUsers() async throws -> [User] {
        return try await makeRequest(endpoint: "/api/users")
    }
    
    func generateInviteLink(role: String) async throws -> InviteLinkResponse {
        struct InviteRequest: Encodable {
            let role: String
        }
        
        let body = try JSONEncoder().encode(InviteRequest(role: role))
        return try await makeRequest(endpoint: "/api/users/generate-invite", method: "POST", body: body)
    }
    
    func deleteUser(userId: String) async throws {
        struct DeleteUserRequest: Encodable {
            let userId: String
        }
        
        let body = try JSONEncoder().encode(DeleteUserRequest(userId: userId))
        let _: [String: Bool] = try await makeRequest(endpoint: "/api/users/delete", method: "DELETE", body: body)
    }
}

// MARK: - Barcode Scanner View
struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Binding var isPresented: Bool
    var onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, BarcodeScannerDelegate {
        let parent: BarcodeScannerView
        
        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }
        
        func didScanCode(_ code: String) {
            parent.scannedCode = code
            parent.onCodeScanned(code)
            parent.isPresented = false
        }
        
        func didCancel() {
            parent.isPresented = false
        }
    }
}

protocol BarcodeScannerDelegate: AnyObject {
    func didScanCode(_ code: String)
    func didCancel()
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: BarcodeScannerDelegate?
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.black
        setupCaptureSession()
        setupUI()
    }
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            failed()
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            failed()
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .pdf417, .code128, .qr, .code39, .code93, .upce]
        } else {
            failed()
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }
    
    private func setupUI() {
        // Add cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        cancelButton.layer.cornerRadius = 20
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        
        view.addSubview(cancelButton)
        
        // Add scanning frame
        let scanningFrame = UIView()
        scanningFrame.layer.borderColor = UIColor.systemGreen.cgColor
        scanningFrame.layer.borderWidth = 3
        scanningFrame.layer.cornerRadius = 15
        scanningFrame.backgroundColor = UIColor.clear
        scanningFrame.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanningFrame)
        
        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "Point camera at barcode"
        instructionLabel.textColor = .white
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        instructionLabel.layer.cornerRadius = 10
        instructionLabel.layer.masksToBounds = true
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            // Cancel button
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 100),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Scanning frame
            scanningFrame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanningFrame.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            scanningFrame.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            scanningFrame.heightAnchor.constraint(equalToConstant: 200),
            
            // Instruction label
            instructionLabel.bottomAnchor.constraint(equalTo: scanningFrame.topAnchor, constant: -20),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.widthAnchor.constraint(equalToConstant: 200),
            instructionLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    @objc func cancelTapped() {
        captureSession?.stopRunning()
        delegate?.didCancel()
    }
    
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if (captureSession?.isRunning == false) {
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            delegate?.didScanCode(stringValue)
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}

// MARK: - Main App
@main
struct InventoryProApp: App {
    @StateObject private var api = APIService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(api)
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var api: APIService
    @State private var refreshID = UUID()
    
    var body: some View {
        Group {
            if api.isAuthenticated {
                MainTabView()
            } else {
                AuthenticationView()
            }
        }
        .id(refreshID)
        .onChange(of: api.isAuthenticated) { _ in
            refreshID = UUID()
        }
    }
}

// MARK: - Authentication Views
struct AuthenticationView: View {
    @EnvironmentObject var api: APIService
    @State private var showingRegistration = false
    
    var body: some View {
        NavigationView {
            if showingRegistration {
                CompanyRegistrationView(showingRegistration: $showingRegistration)
            } else {
                LoginView(showingRegistration: $showingRegistration)
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var api: APIService
    @Binding var showingRegistration: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Logo
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    Text("Inventory Pro")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Professional Inventory Management")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 50)
                
                // Form
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Email", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("user@company.com", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Password", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    Button(action: login) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(isLoading)
                }
                .padding(.horizontal)
                
                // Footer
                VStack(spacing: 20) {
                    Button("Create New Company") {
                        showingRegistration = true
                    }
                    .foregroundColor(.purple)
                    
                    Text("Demo: demo@inventorypro.com / demo123")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationBarHidden(true)
    }
    
    private func login() {
        isLoading = true
        errorMessage = ""
        
        print("🔐 Attempting login with email: \(email)")
        
        Task {
            do {
                try await api.login(email: email, password: password)
                print("✅ Login successful")
            } catch {
                print("❌ Login failed: \(error)")
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct CompanyRegistrationView: View {
    @EnvironmentObject var api: APIService
    @Binding var showingRegistration: Bool
    @State private var companyName = ""
    @State private var adminName = ""
    @State private var adminEmail = ""
    @State private var adminPassword = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    Text("Create Your Company")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Set up your inventory management system")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 30)
                
                // Form
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Company Name", systemImage: "building.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Acme Corporation", text: $companyName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Admin Name", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("John Doe", text: $adminName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Admin Email", systemImage: "envelope.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("admin@company.com", text: $adminEmail)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Admin Password", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Create a strong password", text: $adminPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    Button(action: register) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Create Company")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(isLoading)
                }
                .padding(.horizontal)
                
                // Footer
                Button("Already have an account? Sign In") {
                    showingRegistration = false
                }
                .foregroundColor(.purple)
                .padding(.bottom, 30)
            }
        }
        .navigationBarHidden(true)
    }
    
    private func register() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                try await api.registerCompany(
                    companyName: companyName,
                    adminEmail: adminEmail,
                    adminPassword: adminPassword,
                    adminName: adminName
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @StateObject private var inventoryManager = InventoryManager()
    
    var body: some View {
        TabView {
            ItemsListView()
                .tabItem {
                    Label("Items", systemImage: "list.bullet")
                }
            
            BatchOperationView()
                .tabItem {
                    Label("Operations", systemImage: "shippingbox")
                }
            
            ActivityLogView()
                .tabItem {
                    Label("Activity", systemImage: "clock")
                }
            
            if APIService.shared.currentUser?.role == "admin" {
                TeamManagementView()
                    .tabItem {
                        Label("Team", systemImage: "person.3")
                    }
            }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environmentObject(inventoryManager)
    }
}

// MARK: - Inventory Manager
@MainActor
class InventoryManager: ObservableObject {
    @Published var items: [Item] = []
    @Published var activities: [Activity] = []
    @Published var users: [User] = []
    @Published var isLoading = false
    
    func loadData() async {
        isLoading = true
        do {
            items = try await APIService.shared.getItems()
            activities = try await APIService.shared.getActivities()
            if APIService.shared.currentUser?.role == "admin" {
                users = try await APIService.shared.getUsers()
            }
        } catch {
            print("Error loading data: \(error)")
        }
        isLoading = false
    }
    
    func createItem(name: String, quantity: Int) async throws {
        let barcode = generateBarcode()
        let newItem = try await APIService.shared.createItem(name: name, quantity: quantity, barcode: barcode)
        await loadData()
    }
    
    func updateItemQuantity(item: Item, change: Int) async throws {
        let newQuantity = max(0, item.quantity + change)
        _ = try await APIService.shared.updateItem(id: item.id, quantity: newQuantity)
        await loadData()
    }
    
    func deleteItem(_ item: Item) async throws {
        try await APIService.shared.deleteItem(id: item.id)
        await loadData()
    }
    
    func findItemByBarcode(_ barcode: String) async throws -> Item? {
        return try await APIService.shared.findItemByBarcode(barcode)
    }
    
    func getItemActivities(itemId: String) async throws -> [Activity] {
        return try await APIService.shared.getItemActivities(itemId: itemId)
    }
    
    func getDefaultLowStockThreshold() -> Int {
        return APIService.shared.currentCompany?.lowStockThreshold ?? 5
    }
    
    func isLowStock(_ item: Item) -> Bool {
        let threshold = item.lowStockThreshold ?? getDefaultLowStockThreshold()
        return item.quantity <= threshold && item.quantity > 0
    }
    
    func isOutOfStock(_ item: Item) -> Bool {
        return item.quantity <= 0
    }
    
    private func generateBarcode() -> String {
        let companyCode = APIService.shared.currentCompany?.code ?? "INV"
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(companyCode)-\(String(timestamp).suffix(6))"
    }
}

// MARK: - Items List View
struct ItemsListView: View {
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var searchText = ""
    @State private var filterOption = "all"
    @State private var showingScanner = false
    @State private var showingBarcodeEntry = false
    @State private var scannedBarcode: String?
    @State private var selectedItem: Item?
    @State private var showingItemDetail = false
    
    var filteredItems: [Item] {
        let items = inventoryManager.items
        
        let searchFiltered = searchText.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.barcode.localizedCaseInsensitiveContains(searchText)
        }
        
        switch filterOption {
        case "lowStock":
            return searchFiltered.filter { inventoryManager.isLowStock($0) }
        case "outOfStock":
            return searchFiltered.filter { inventoryManager.isOutOfStock($0) }
        default:
            return searchFiltered
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Stats Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("All Items")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        if inventoryManager.items.isEmpty {
                            Text("No items in your inventory")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            let totalUnits = inventoryManager.items.reduce(0) { $0 + $1.quantity }
                            Text("\(inventoryManager.items.count) items · \(totalUnits) total units")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: { showingBarcodeEntry = true }) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                        }
                        
                        Button(action: { showingScanner = true }) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                
                // Search and Filter
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search items by name or barcode...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    
                    Picker("Filter", selection: $filterOption) {
                        Text("All Items").tag("all")
                        Text("Low Stock").tag("lowStock")
                        Text("Out of Stock").tag("outOfStock")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                
                // Items List
                if inventoryManager.isLoading {
                    Spacer()
                    ProgressView("Loading items...")
                    Spacer()
                } else if filteredItems.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: searchText.isEmpty ? "shippingbox" : "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text(searchText.isEmpty ? "No items yet" : "No items found")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text(searchText.isEmpty ? "Add your first item to get started" : "Try adjusting your search or filter")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if searchText.isEmpty {
                            NavigationLink(destination: AddItemView()) {
                                Label("Add Your First Item", systemImage: "plus")
                                    .padding()
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    Spacer()
                } else {
                    List(filteredItems) { item in
                        ItemRowView(item: item)
                            .onTapGesture {
                                selectedItem = item
                                showingItemDetail = true
                            }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView(scannedCode: $scannedBarcode, isPresented: $showingScanner) { barcode in
                    handleScannedBarcode(barcode)
                }
            }
            .sheet(isPresented: $showingBarcodeEntry) {
                BarcodeEntryView(onBarcodeEntered: handleScannedBarcode)
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item)
            }
        }
        .onAppear {
            Task {
                await inventoryManager.loadData()
            }
        }
    }
    
    private func handleScannedBarcode(_ barcode: String) {
        Task {
            do {
                if let item = try await inventoryManager.findItemByBarcode(barcode) {
                    selectedItem = item
                    showingItemDetail = true
                } else {
                    print("Item not found")
                }
            } catch {
                print("Error finding item: \(error)")
            }
        }
    }
}

struct ItemRowView: View {
    let item: Item
    @EnvironmentObject var inventoryManager: InventoryManager
    
    var stockColor: Color {
        if inventoryManager.isOutOfStock(item) { return .red }
        if inventoryManager.isLowStock(item) { return .orange }
        return .green
    }
    
    var stockStatus: String {
        if inventoryManager.isOutOfStock(item) { return "Out of Stock" }
        if inventoryManager.isLowStock(item) { return "Low Stock" }
        return "In Stock"
    }
    
    var body: some View {
        HStack {
            // Item Icon
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundColor(.purple)
                .frame(width: 40, height: 40)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                
                HStack {
                    Text(item.barcode)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    if let updatedAt = item.updatedAt {
                        Text(formatDate(updatedAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(item.quantity)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(stockColor)
                
                Text(stockStatus)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(stockColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(stockColor.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
}

// MARK: - Barcode Entry View
struct BarcodeEntryView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var barcode = ""
    let onBarcodeEntered: (String) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Enter Barcode Manually")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Barcode", systemImage: "barcode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., INV-000001", text: $barcode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                }
                .padding(.horizontal)
                
                Button(action: {
                    if !barcode.isEmpty {
                        onBarcodeEntered(barcode)
                        presentationMode.wrappedValue.dismiss()
                    }
                }) {
                    Text("Look Up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .disabled(barcode.isEmpty)
                
                Spacer()
            }
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Batch Operation View (NEW)
struct BatchOperationView: View {
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var sessionTitle = ""
    @State private var selectedItems: [BatchItem] = []
    @State private var showingScanner = false
    @State private var showingItemPicker = false
    @State private var showingAddItem = false
    @State private var isProcessing = false
    @State private var showingSuccessAlert = false
    
    struct BatchItem: Identifiable {
        let id = UUID()
        var item: Item
        var quantityChange: Int = 0
        var action: String = "add" // "add" or "remove"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Text("Inventory Operations")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Operation Title", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., Weekly restocking, Damaged goods removal", text: $sessionTitle)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.horizontal)
                }
                .padding()
                .background(Color(.systemBackground))
                
                // Add Item Buttons
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button(action: { showingScanner = true }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Scan Item")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        Button(action: { showingItemPicker = true }) {
                            HStack {
                                Image(systemName: "list.bullet")
                                Text("Browse Items")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    Button(action: { showingAddItem = true }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Create New Item")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                
                // Selected Items List
                if selectedItems.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No items selected")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Scan or browse items to add them to this operation")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(selectedItems) { batchItem in
                            BatchItemRowView(batchItem: batchItem) { updatedItem in
                                if let index = selectedItems.firstIndex(where: { $0.id == updatedItem.id }) {
                                    selectedItems[index] = updatedItem
                                }
                            } onRemove: {
                                selectedItems.removeAll { $0.id == batchItem.id }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    
                    // Process Button
                    VStack {
                        Button(action: processOperation) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Process Operation (\(selectedItems.count) items)")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(sessionTitle.isEmpty ? Color.gray : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .disabled(sessionTitle.isEmpty || selectedItems.isEmpty || isProcessing)
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView(scannedCode: .constant(nil), isPresented: $showingScanner) { barcode in
                    handleScannedBarcode(barcode)
                }
            }
            .sheet(isPresented: $showingItemPicker) {
                ItemPickerView { item in
                    addItemToBatch(item)
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddItemView()
            }
            .alert("Operation Complete", isPresented: $showingSuccessAlert) {
                Button("OK") {
                    // Reset form
                    sessionTitle = ""
                    selectedItems = []
                }
            } message: {
                Text("Successfully processed \(selectedItems.count) items")
            }
        }
        .onAppear {
            Task {
                await inventoryManager.loadData()
            }
        }
    }
    
    private func handleScannedBarcode(_ barcode: String) {
        Task {
            do {
                if let item = try await inventoryManager.findItemByBarcode(barcode) {
                    addItemToBatch(item)
                } else {
                    print("Item not found")
                }
            } catch {
                print("Error finding item: \(error)")
            }
        }
    }
    
    private func addItemToBatch(_ item: Item) {
        if !selectedItems.contains(where: { $0.item.id == item.id }) {
            selectedItems.append(BatchItem(item: item))
        }
    }
    
    private func processOperation() {
        guard !sessionTitle.isEmpty else { return }
        
        isProcessing = true
        
        Task {
            do {
                let operations = selectedItems.map { batchItem in
                    let change = batchItem.action == "add" ? batchItem.quantityChange : -batchItem.quantityChange
                    return (itemId: batchItem.item.id, quantityChange: change)
                }
                
                try await APIService.shared.createBatchActivity(sessionTitle: sessionTitle, items: operations)
                await inventoryManager.loadData()
                
                showingSuccessAlert = true
            } catch {
                print("Error processing operation: \(error)")
            }
            
            isProcessing = false
        }
    }
}

struct BatchItemRowView: View {
    let batchItem: BatchOperationView.BatchItem
    let onUpdate: (BatchOperationView.BatchItem) -> Void
    let onRemove: () -> Void
    
    @State private var localQuantity: String
    @State private var localAction: String
    
    init(batchItem: BatchOperationView.BatchItem, onUpdate: @escaping (BatchOperationView.BatchItem) -> Void, onRemove: @escaping () -> Void) {
        self.batchItem = batchItem
        self.onUpdate = onUpdate
        self.onRemove = onRemove
        self._localQuantity = State(initialValue: String(abs(batchItem.quantityChange)))
        self._localAction = State(initialValue: batchItem.action)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(batchItem.item.name)
                    .font(.headline)
                
                Spacer()
                
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                Text("Current: \(batchItem.item.quantity)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(batchItem.item.barcode)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                Picker("Action", selection: $localAction) {
                    Text("Add").tag("add")
                    Text("Remove").tag("remove")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 120)
                
                TextField("Qty", text: $localQuantity)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                
                Text(localAction == "add" ? "items" : "items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .onChange(of: localQuantity) { _ in
            updateBatchItem()
        }
        .onChange(of: localAction) { _ in
            updateBatchItem()
        }
    }
    
    private func updateBatchItem() {
        var updated = batchItem
        updated.quantityChange = Int(localQuantity) ?? 0
        updated.action = localAction
        onUpdate(updated)
    }
}

struct ItemPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var searchText = ""
    let onItemSelected: (Item) -> Void
    
    var filteredItems: [Item] {
        if searchText.isEmpty {
            return inventoryManager.items
        } else {
            return inventoryManager.items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.barcode.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search items...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding()
                
                // Items List
                List(filteredItems) { item in
                    Button(action: {
                        onItemSelected(item)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("\(item.quantity) in stock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(item.barcode)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select Item")
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Add Item View
struct AddItemView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var itemName = ""
    @State private var quantity = "1"
    @State private var isLoading = false
    @State private var showingPrintDialog = false
    @State private var createdItem: Item?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Item Details")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Item Name", systemImage: "cube")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Enter item name", text: $itemName)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Initial Quantity", systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("1", text: $quantity)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section {
                    Button(action: createItem) {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Spacer()
                            }
                        } else {
                            Text("Create Item")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(itemName.isEmpty || isLoading)
                    .foregroundColor(itemName.isEmpty ? .secondary : .white)
                    .listRowBackground(itemName.isEmpty ? Color.secondary.opacity(0.3) : Color.purple)
                }
            }
            .navigationTitle("Add New Item")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .alert("Print Barcode Label?", isPresented: $showingPrintDialog) {
            Button("Print") {
                // Print functionality would go here
                presentationMode.wrappedValue.dismiss()
            }
            Button("Skip") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            if let item = createdItem {
                Text("Would you like to print a barcode label for \(item.name)?")
            }
        }
    }
    
    private func createItem() {
        isLoading = true
        
        Task {
            do {
                let qty = Int(quantity) ?? 1
                try await inventoryManager.createItem(name: itemName, quantity: qty)
                
                // Show print dialog
                showingPrintDialog = true
            } catch {
                print("Error creating item: \(error)")
            }
            isLoading = false
        }
    }
}

// MARK: - Item Detail View (UPDATED)
struct ItemDetailView: View {
    let item: Item
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var adjustQuantity = 1
    @State private var adjustAction = "remove"
    @State private var isUpdating = false
    @State private var showingActivityLog = false
    @State private var itemActivities: [Activity] = []
    @State private var lowStockThreshold: Double = 5
    @State private var showingThresholdSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Item Info
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    Text(item.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Current Stock: \(item.quantity)")
                        .font(.title3)
                        .foregroundColor(inventoryManager.isLowStock(item) ? .orange : .green)
                }
                .padding()
                
                // Stock Status
                HStack {
                    Image(systemName: inventoryManager.isOutOfStock(item) ? "exclamationmark.triangle.fill" :
                          inventoryManager.isLowStock(item) ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(inventoryManager.isOutOfStock(item) ? .red :
                                       inventoryManager.isLowStock(item) ? .orange : .green)
                    
                    Text(inventoryManager.isOutOfStock(item) ? "Out of Stock" :
                         inventoryManager.isLowStock(item) ? "Low Stock" : "In Stock")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if APIService.shared.currentUser?.role == "admin" {
                        Button("Settings") {
                            lowStockThreshold = Double(item.lowStockThreshold ?? inventoryManager.getDefaultLowStockThreshold())
                            showingThresholdSettings = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                
                // Barcode
                VStack(spacing: 8) {
                    Text("Barcode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(item.barcode)
                        .font(.system(.headline, design: .monospaced))
                    
                    // Barcode visual
                    GeometryReader { geometry in
                        HStack(spacing: 1) {
                            ForEach(0..<50, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: geometry.size.width / 100)
                            }
                        }
                    }
                    .frame(height: 60)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black, Color.black]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .mask(
                            HStack(spacing: 1) {
                                ForEach(0..<50, id: \.self) { i in
                                    Rectangle()
                                        .fill(i % 2 == 0 ? Color.black : Color.clear)
                                }
                            }
                        )
                    )
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button(action: { showingActivityLog = true }) {
                        VStack {
                            Image(systemName: "clock.fill")
                            Text("Activity Log")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    Button(action: performQuickAdjustment) {
                        VStack {
                            Image(systemName: "plus.minus")
                            Text("Quick Adjust")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                // Adjustment Controls
                VStack(spacing: 16) {
                    Text("Adjust Inventory")
                        .font(.headline)
                    
                    Picker("Action", selection: $adjustAction) {
                        Text("Remove").tag("remove")
                        Text("Add").tag("add")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    HStack {
                        Button(action: {
                            if adjustQuantity > 1 {
                                adjustQuantity -= 1
                            }
                        }) {
                            Image(systemName: "minus.circle")
                                .font(.title)
                        }
                        
                        Text("\(adjustQuantity)")
                            .font(.title)
                            .fontWeight(.semibold)
                            .frame(minWidth: 60)
                        
                        Button(action: {
                            adjustQuantity += 1
                        }) {
                            Image(systemName: "plus.circle")
                                .font(.title)
                        }
                    }
                    
                    Button(action: performAdjustment) {
                        if isUpdating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(adjustAction == "add" ? "Add Items" : "Remove Items")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(adjustAction == "add" ? Color.green : Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(isUpdating || (adjustAction == "remove" && adjustQuantity > item.quantity))
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .sheet(isPresented: $showingActivityLog) {
            ItemActivityView(item: item, activities: itemActivities)
        }
        .sheet(isPresented: $showingThresholdSettings) {
            LowStockThresholdView(
                item: item,
                threshold: $lowStockThreshold,
                onSave: { newThreshold in
                    Task {
                        do {
                            _ = try await APIService.shared.updateItemLowStockThreshold(
                                id: item.id,
                                threshold: Int(newThreshold)
                            )
                            await inventoryManager.loadData()
                        } catch {
                            print("Error updating threshold: \(error)")
                        }
                    }
                }
            )
        }
        .onAppear {
            loadItemActivities()
        }
    }
    
    private func performAdjustment() {
        isUpdating = true
        let change = adjustAction == "add" ? adjustQuantity : -adjustQuantity
        
        Task {
            do {
                try await inventoryManager.updateItemQuantity(item: item, change: change)
                presentationMode.wrappedValue.dismiss()
            } catch {
                print("Error updating item: \(error)")
            }
            isUpdating = false
        }
    }
    
    private func performQuickAdjustment() {
        // Quick +1/-1 adjustment
        Task {
            do {
                try await inventoryManager.updateItemQuantity(item: item, change: item.quantity > 0 ? -1 : 1)
            } catch {
                print("Error updating item: \(error)")
            }
        }
    }
    
    private func loadItemActivities() {
        Task {
            do {
                itemActivities = try await inventoryManager.getItemActivities(itemId: item.id)
            } catch {
                print("Error loading item activities: \(error)")
            }
        }
    }
}

// MARK: - Item Activity View (NEW)
struct ItemActivityView: View {
    let item: Item
    let activities: [Activity]
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Group {
                if activities.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No activity recorded")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text("Activity for \(item.name) will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(activities) { activity in
                        ActivityRowView(activity: activity)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("\(item.name) Activity")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Low Stock Threshold View (NEW)
struct LowStockThresholdView: View {
    let item: Item
    @Binding var threshold: Double
    let onSave: (Double) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Low Stock Alert")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("Set the quantity threshold for \(item.name)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    HStack {
                        Text("Alert when quantity is at or below:")
                        Spacer()
                        Text("\(Int(threshold))")
                            .fontWeight(.bold)
                    }
                    
                    Slider(value: $threshold, in: 0...50, step: 1)
                        .accentColor(.orange)
                    
                    HStack {
                        Text("0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("50")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                
                Button(action: {
                    onSave(threshold)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Save Setting")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Activity Log View
struct ActivityLogView: View {
    @EnvironmentObject var inventoryManager: InventoryManager
    
    var body: some View {
        NavigationView {
            Group {
                if inventoryManager.activities.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No activity recorded yet")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(inventoryManager.activities) { activity in
                        ActivityRowView(activity: activity)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Activity Log")
        }
        .onAppear {
            Task {
                await inventoryManager.loadData()
            }
        }
    }
}

struct ActivityRowView: View {
    let activity: Activity
    
    var activityColor: Color {
        switch activity.type {
        case "created": return .green
        case "added": return .blue
        case "removed": return .orange
        case "deleted": return .red
        default: return .gray
        }
    }
    
    var activityDescription: String {
        switch activity.type {
        case "created":
            return "Created with initial quantity of \(activity.quantity ?? 0)"
        case "added":
            return "Added \(activity.quantity ?? 0) items (was \(activity.oldQuantity ?? 0))"
        case "removed":
            return "Removed \(activity.quantity ?? 0) items (was \(activity.oldQuantity ?? 0))"
        case "deleted":
            return "Deleted item (had \(activity.quantity ?? 0) items)"
        default:
            return activity.type
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.type.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(activityColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(activityColor.opacity(0.1))
                    .cornerRadius(4)
                
                Text(activity.itemName)
                    .font(.headline)
                
                Spacer()
            }
            
            if let sessionTitle = activity.sessionTitle {
                Text("📋 \(sessionTitle)")
                    .font(.subheadline)
                    .foregroundColor(.purple)
                    .fontWeight(.medium)
            }
            
            Text(activityDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let createdAt = activity.createdAt, let userName = activity.userName {
                Text("By \(userName) • \(formatDate(createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
}

// MARK: - Team Management View (UPDATED)
struct TeamManagementView: View {
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var showingInviteGenerator = false
    
    var body: some View {
        NavigationView {
            VStack {
                if inventoryManager.users.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.3")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No team members yet")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Button(action: { showingInviteGenerator = true }) {
                            Label("Generate Invite Link", systemImage: "link")
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                } else {
                    List(inventoryManager.users) { user in
                        UserRowView(user: user)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Team Management")
            .navigationBarItems(
                trailing: Button(action: { showingInviteGenerator = true }) {
                    Image(systemName: "link")
                }
            )
            .sheet(isPresented: $showingInviteGenerator) {
                InviteLinkGeneratorView()
            }
        }
        .onAppear {
            Task {
                await inventoryManager.loadData()
            }
        }
    }
}

struct UserRowView: View {
    let user: User
    @EnvironmentObject var inventoryManager: InventoryManager
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.purple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.headline)
                
                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(user.role == "admin" ? "Administrator" : "User")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
                
                if let createdAt = user.createdAt {
                    Text(formatDate(createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
}

// MARK: - Invite Link Generator View (SIMPLIFIED)
struct InviteLinkGeneratorView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var selectedRole = "user"
    @State private var isGenerating = false
    @State private var generatedLink: String?
    @State private var showingCopyConfirmation = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    Text("Generate Invite Link")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Create a secure invitation link that new team members can use to join your company via our website")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Role Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Role")
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        HStack {
                            Button(action: { selectedRole = "user" }) {
                                HStack {
                                    Image(systemName: selectedRole == "user" ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedRole == "user" ? .purple : .secondary)
                                    
                                    VStack(alignment: .leading) {
                                        Text("Team Member")
                                            .fontWeight(.medium)
                                        Text("Can view and manage inventory")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .padding()
                        .background(selectedRole == "user" ? Color.purple.opacity(0.1) : Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        
                        HStack {
                            Button(action: { selectedRole = "admin" }) {
                                HStack {
                                    Image(systemName: selectedRole == "admin" ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedRole == "admin" ? .purple : .secondary)
                                    
                                    VStack(alignment: .leading) {
                                        Text("Administrator")
                                            .fontWeight(.medium)
                                        Text("Full access including team management")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .padding()
                        .background(selectedRole == "admin" ? Color.purple.opacity(0.1) : Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // Generated Link Section
                if let link = generatedLink {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Invitation Link Created!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Share this link with your team member:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(link)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .textSelection(.enabled)
                            }
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    UIPasteboard.general.string = link
                                    showingCopyConfirmation = true
                                }) {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Link")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                
                                Button(action: shareLink) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Share")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("📝 How it works:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Text("• Send this link to your team member")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("• They'll open it in their browser")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("• They'll create their account on the website")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("• They can then download the app or use the web version")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                } else {
                    // Generate Button
                    Button(action: generateInviteLink) {
                        if isGenerating {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating...")
                            }
                        } else {
                            Text("Generate Invite Link")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(isGenerating)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: generatedLink != nil ? Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                } : nil
            )
        }
        .alert("Link Copied!", isPresented: $showingCopyConfirmation) {
            Button("OK") {}
        } message: {
            Text("The invitation link has been copied to your clipboard")
        }
    }
    
    private func generateInviteLink() {
        isGenerating = true
        errorMessage = ""
        
        Task {
            do {
                let response = try await APIService.shared.generateInviteLink(role: selectedRole)
                
                await MainActor.run {
                    self.generatedLink = response.inviteUrl
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to generate invite link: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }
    
    private func shareLink() {
        guard let link = generatedLink else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [
                "Join our inventory management team! Use this link to create your account: \(link)"
            ],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

// MARK: - Settings View (UPDATED)
struct SettingsView: View {
    @EnvironmentObject var api: APIService
    @State private var showingLogoutAlert = false
    @State private var showingLowStockSettings = false
    @State private var defaultLowStockThreshold: Double = 5
    
    var body: some View {
        NavigationView {
            Form {
                // Company Info Section
                Section(header: Text("Company Information")) {
                    HStack {
                        Text("Company Name")
                        Spacer()
                        Text(api.currentCompany?.name ?? "N/A")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Company Code")
                        Spacer()
                        Text(api.currentCompany?.code ?? "N/A")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Low Stock Settings (Admin only)
                if api.currentUser?.role == "admin" {
                    Section(header: Text("Inventory Settings")) {
                        HStack {
                            Text("Default Low Stock Threshold")
                            Spacer()
                            Text("\(api.currentCompany?.lowStockThreshold ?? 5)")
                                .foregroundColor(.secondary)
                        }
                        
                        Button("Configure Low Stock Alerts") {
                            defaultLowStockThreshold = Double(api.currentCompany?.lowStockThreshold ?? 5)
                            showingLowStockSettings = true
                        }
                    }
                }
                
                // User Info Section
                Section(header: Text("Account")) {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(api.currentUser?.name ?? "N/A")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(api.currentUser?.email ?? "N/A")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Role")
                        Spacer()
                        Text(api.currentUser?.role == "admin" ? "Administrator" : "User")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Actions Section
                Section {
                    Button(action: { showingLogoutAlert = true }) {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "arrow.right.square")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Sign Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    api.logout()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .sheet(isPresented: $showingLowStockSettings) {
                CompanyLowStockSettingsView(threshold: $defaultLowStockThreshold)
            }
        }
    }
}

// MARK: - Company Low Stock Settings View (NEW)
struct CompanyLowStockSettingsView: View {
    @Binding var threshold: Double
    @Environment(\.presentationMode) var presentationMode
    @State private var isUpdating = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Default Low Stock Alert")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Set the default threshold for low stock alerts across all items. Individual items can have their own custom thresholds.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                VStack(spacing: 16) {
                    HStack {
                        Text("Alert when quantity is at or below:")
                        Spacer()
                        Text("\(Int(threshold))")
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    
                    Slider(value: $threshold, in: 0...50, step: 1)
                        .accentColor(.orange)
                    
                    HStack {
                        Text("0 (Disabled)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("50")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Button(action: saveThreshold) {
                    if isUpdating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Save Default Threshold")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isUpdating)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func saveThreshold() {
        isUpdating = true
        errorMessage = ""
        
        Task {
            do {
                _ = try await APIService.shared.updateCompanyLowStockThreshold(Int(threshold))
                
                await MainActor.run {
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to update threshold: \(error.localizedDescription)"
                    isUpdating = false
                }
            }
        }
    }
}

// MARK: - Helper Extensions
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
