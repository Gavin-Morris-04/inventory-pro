import SwiftUI
import AVFoundation
import Combine

/// MARK: - Models
struct User: Codable, Identifiable {
    let id: String  // Changed from Int to String
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
    let id: String  // Changed from Int to String
    let name: String
    let code: String
    let subscriptionTier: String
    let maxUsers: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, code
        case subscriptionTier = "subscription_tier"
        case maxUsers = "max_users"
    }
}

struct Item: Codable, Identifiable {
    let id: String  // Changed from Int to String
    let name: String
    var quantity: Int
    let barcode: String
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, quantity, barcode
        case updatedAt = "updated_at"
    }
}

struct Activity: Codable, Identifiable {
    let id: String  // Changed from Int to String
    let itemName: String
    let type: String
    let quantity: Int?
    let oldQuantity: Int?
    let userName: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, type, quantity
        case itemName = "item_name"
        case oldQuantity = "old_quantity"
        case userName = "user_name"
        case createdAt = "created_at"
    }
}

/// MARK: - API Service
@MainActor
class APIService: ObservableObject {
    static let shared = APIService()
    private let baseURL = "https://inventory-pro-backend-production.up.railway.app"
    
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
    
    // MARK: - Company
    func getCompanyInfo() async throws -> Company {
        struct CompanyResponse: Decodable {
            let company: Company
        }
        let response: CompanyResponse = try await makeRequest(endpoint: "/api/companies/info")
        return response.company
    }
    
    // MARK: - Users
    func getUsers() async throws -> [User] {
        return try await makeRequest(endpoint: "/api/users")
    }
    
    func inviteUser(email: String, name: String, role: String) async throws {
        struct InviteRequest: Encodable {
            let email: String
            let name: String
            let role: String
        }
        
        struct InviteResponse: Decodable {
            let success: Bool
            let message: String
            let invitationId: String
            let emailSent: Bool
            let emailMethod: String?
            let emailError: String?
            let manualInvitationData: ManualInvitationData?
            let invitationLink: String?
        }
        
        struct ManualInvitationData: Decodable {
            let to: String
            let from: String
            let link: String
        }
        
        print("📧 Sending invitation to: \(email)")
        
        let body = try JSONEncoder().encode(InviteRequest(email: email, name: name, role: role))
        let response: InviteResponse = try await makeRequest(endpoint: "/api/users/invite", method: "POST", body: body)
        
        print("✅ Invitation response: \(response.message)")
        print("📧 Email sent: \(response.emailSent)")
        
        if response.emailSent {
            print("📮 Email delivered via: \(response.emailMethod ?? "unknown")")
        } else {
            print("⚠️ Email failed to send: \(response.emailError ?? "unknown error")")
            
            // Handle manual invitation fallback
            if let manualData = response.manualInvitationData {
                print("📋 Manual invitation required:")
                print("   To: \(manualData.to)")
                print("   From: \(manualData.from)")
                print("   Link: \(manualData.link)")
            } else if let invitationLink = response.invitationLink {
                print("📋 Share this link manually: \(invitationLink)")
            }
        }
    }
    
    func testEmailConfiguration() async throws -> Bool {
        struct TestEmailRequest: Encodable {
            let testType: String = "email_config"
        }
        
        struct TestEmailResponse: Decodable {
            let success: Bool
            let emailConfigured: Bool
            let message: String
        }
        
        do {
            let body = try JSONEncoder().encode(TestEmailRequest())
            let response: TestEmailResponse = try await makeRequest(endpoint: "/api/test/email", method: "POST", body: body)
            
            print("📧 Email config test: \(response.message)")
            return response.emailConfigured
        } catch {
            print("❌ Email config test failed: \(error)")
            return false
        }
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
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
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
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .pdf417, .code128, .qr]
        } else {
            failed()
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
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
        
        NSLayoutConstraint.activate([
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 100),
            cancelButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Add scanning frame
        let scanningFrame = UIView()
        scanningFrame.layer.borderColor = UIColor.systemPurple.cgColor
        scanningFrame.layer.borderWidth = 2
        scanningFrame.layer.cornerRadius = 10
        scanningFrame.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanningFrame)
        
        NSLayoutConstraint.activate([
            scanningFrame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanningFrame.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            scanningFrame.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            scanningFrame.heightAnchor.constraint(equalToConstant: 150)
        ])
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }
    
    @objc func cancelTapped() {
        captureSession.stopRunning()
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
        
        dismiss(animated: true)
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
    @State private var refreshID = UUID() // Add this
    
    var body: some View {
        Group {
            if api.isAuthenticated {
                MainTabView()
            } else {
                AuthenticationView()
            }
        }
        .id(refreshID) // Add this
        .onChange(of: api.isAuthenticated) { _ in
            refreshID = UUID() // Force view refresh
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
                    Button("Start Free Trial") {
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
    @State private var companySize = "small"
    @State private var adminName = ""
    @State private var adminEmail = ""
    @State private var adminPassword = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    let companySizes = [
        ("small", "1-10 employees"),
        ("medium", "11-50 employees"),
        ("large", "51-200 employees"),
        ("enterprise", "200+ employees")
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    Text("Start Your Free Trial")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Professional inventory management for your business")
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
                        Label("Company Size", systemImage: "person.3.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Company Size", selection: $companySize) {
                            ForEach(companySizes, id: \.0) { size in
                                Text(size.1).tag(size.0)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
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
                    
                    // Features
                    VStack(alignment: .leading, spacing: 10) {
                        Text("✨ What's Included:")
                            .font(.headline)
                            .foregroundColor(.purple)
                        
                        ForEach([
                            "30-day free trial - no credit card required",
                            "Unlimited users and inventory items",
                            "Real-time barcode scanning",
                            "Multi-location support",
                            "Analytics and reporting",
                            "24/7 customer support"
                        ], id: \.self) { feature in
                            HStack(alignment: .top, spacing: 5) {
                                Text("✓")
                                    .foregroundColor(.green)
                                Text(feature)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(10)
                    
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
                            Text("Start Free Trial")
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
            
            InventoryManagementView()
                .tabItem {
                    Label("Manage", systemImage: "shippingbox")
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
    
    var filteredItems: [Item] {
        let items = inventoryManager.items
        
        let searchFiltered = searchText.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.barcode.localizedCaseInsensitiveContains(searchText)
        }
        
        switch filterOption {
        case "lowStock":
            return searchFiltered.filter { $0.quantity > 0 && $0.quantity <= 5 }
        case "outOfStock":
            return searchFiltered.filter { $0.quantity == 0 }
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
                            NavigationLink(destination: InventoryManagementView()) {
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
                    // Navigate to item detail or show update dialog
                    print("Found item: \(item.name)")
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
    
    var stockColor: Color {
        if item.quantity <= 0 { return .red }
        if item.quantity <= 5 { return .orange }
        return .green
    }
    
    var stockStatus: String {
        if item.quantity <= 0 { return "Out of Stock" }
        if item.quantity <= 5 { return "Low Stock" }
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

// MARK: - Inventory Management View
struct InventoryManagementView: View {
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var showingAddForm = false
    @State private var showingScanner = false
    @State private var scannedBarcode: String?
    @State private var selectedItem: Item?
    @State private var showingItemDetail = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Action Buttons
                HStack(spacing: 16) {
                    Button(action: { showingAddForm = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Item")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
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
                }
                .padding()
                
                // Items Grid
                if inventoryManager.items.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No items in inventory")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Add your first item to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(inventoryManager.items) { item in
                                ItemCardView(item: item)
                                    .onTapGesture {
                                        selectedItem = item
                                        showingItemDetail = true
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Manage Inventory")
            .sheet(isPresented: $showingAddForm) {
                AddItemView()
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView(scannedCode: $scannedBarcode, isPresented: $showingScanner) { barcode in
                    Task {
                        do {
                            if let item = try await inventoryManager.findItemByBarcode(barcode) {
                                selectedItem = item
                                showingItemDetail = true
                            }
                        } catch {
                            print("Error finding item: \(error)")
                        }
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item)
            }
        }
    }
}

struct ItemCardView: View {
    let item: Item
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var isUpdating = false
    
    var stockColor: Color {
        if item.quantity <= 0 { return .red }
        if item.quantity <= 5 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)
                
                Spacer()
                
                Menu {
                    Button(role: .destructive) {
                        Task {
                            try await inventoryManager.deleteItem(item)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Quantity: \(item.quantity)")
                .font(.subheadline)
                .foregroundColor(stockColor)
                .fontWeight(.medium)
            
            // Barcode
            VStack(spacing: 4) {
                Text(item.barcode)
                    .font(.caption2)
                    .fontWeight(.medium)
                
                // Barcode visual
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(0..<30, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: geometry.size.width / 60)
                        }
                    }
                }
                .frame(height: 30)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black, Color.black]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask(
                        HStack(spacing: 1) {
                            ForEach(0..<30, id: \.self) { i in
                                Rectangle()
                                    .fill(i % 2 == 0 ? Color.black : Color.clear)
                            }
                        }
                    )
                )
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(6)
            
            // Quantity Controls
            HStack {
                Button(action: {
                    updateQuantity(-1)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
                .disabled(item.quantity <= 0 || isUpdating)
                
                Spacer()
                
                Text("\(item.quantity)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(minWidth: 50)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Spacer()
                
                Button(action: {
                    updateQuantity(1)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
                .disabled(isUpdating)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private func updateQuantity(_ change: Int) {
        isUpdating = true
        Task {
            do {
                try await inventoryManager.updateItemQuantity(item: item, change: change)
            } catch {
                print("Error updating quantity: \(error)")
            }
            isUpdating = false
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

// MARK: - Item Detail View
struct ItemDetailView: View {
    let item: Item
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var adjustQuantity = 1
    @State private var adjustAction = "remove"
    @State private var isUpdating = false
    
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
                        .foregroundColor(item.quantity <= 5 ? .orange : .green)
                }
                .padding()
                
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

// MARK: - Team Management View
struct TeamManagementView: View {
    @EnvironmentObject var inventoryManager: InventoryManager
    @State private var showingInviteUser = false
    
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
                        
                        Button(action: { showingInviteUser = true }) {
                            Label("Invite User", systemImage: "plus")
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
                trailing: Button(action: { showingInviteUser = true }) {
                    Image(systemName: "plus")
                }
            )
            .sheet(isPresented: $showingInviteUser) {
                InviteUserView()
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

    // MARK: - Enhanced InviteUserView with Email Status
    // Replace your existing InviteUserView with this enhanced version

    // MARK: - REPLACE your existing InviteUserView with this fixed version

    struct InviteUserView: View {
        @Environment(\.presentationMode) var presentationMode
        @EnvironmentObject var inventoryManager: InventoryManager
        @State private var name = ""
        @State private var email = ""
        @State private var role = "user"
        @State private var isLoading = false
        @State private var errorMessage = ""
        @State private var successMessage = ""
        @State private var showEmailStatus = false
        @State private var emailSent = false
        @State private var manualInviteLink: String? = nil
        @State private var emailError: String? = nil
        @State private var emailConfigured = true
        
        var body: some View {
            NavigationView {
                Form {
                    // User Details Section
                    Section(header: Text("User Details")) {
                        TextField("Full Name", text: $name)
                            .disabled(isLoading)
                        
                        TextField("Email Address", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disabled(isLoading)
                        
                        Picker("Role", selection: $role) {
                            Text("User").tag("user")
                            Text("Administrator").tag("admin")
                        }
                        .disabled(isLoading)
                    }
                    
                    // Email Status Section
                    if showEmailStatus {
                        Section(header: Text("Invitation Status")) {
                            if emailSent {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading) {
                                        Text("Email invitation sent successfully!")
                                            .foregroundColor(.green)
                                            .font(.headline)
                                        Text("The user will receive an email from your address with instructions to join.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Email could not be sent")
                                            .foregroundColor(.orange)
                                            .font(.headline)
                                    }
                                    
                                    if let error = emailError {
                                        Text("Error: \(error)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let link = manualInviteLink {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Please share this invitation manually:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Text(link)
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(6)
                                            
                                            Button("Copy Link") {
                                                UIPasteboard.general.string = link
                                            }
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Error/Success Messages
                    if !errorMessage.isEmpty {
                        Section {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    
                    if !successMessage.isEmpty {
                        Section {
                            Text(successMessage)
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                    
                    // Send Invitation Button
                    Section {
                        Button(action: inviteUser) {
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Sending Invitation...")
                                }
                            } else {
                                Text("Send Invitation")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(name.isEmpty || email.isEmpty || isLoading)
                        .foregroundColor(name.isEmpty || email.isEmpty ? .secondary : .white)
                        .listRowBackground(name.isEmpty || email.isEmpty ? Color.secondary.opacity(0.3) : Color.purple)
                    }
                    
                    // Footer Information
                    Section(footer: Text(emailConfigured ?
                        "An invitation email will be sent from your email address to the new user." :
                        "Email service is not configured. You'll receive a link to share manually.")) {
                        EmptyView()
                    }
                }
                .navigationTitle("Invite User")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            }
            .onAppear {
                checkEmailConfiguration()
            }
        }
        
        private func inviteUser() {
            guard !email.isEmpty && !name.isEmpty else {
                errorMessage = "Please fill in all fields"
                return
            }
            
            isLoading = true
            errorMessage = ""
            successMessage = ""
            showEmailStatus = false
            manualInviteLink = nil
            emailError = nil
            
            Task {
                do {
                    print("📧 Attempting to invite user...")
                    try await APIService.shared.inviteUser(
                        email: email,
                        name: name,
                        role: role
                    )
                    
                    await MainActor.run {
                        successMessage = "Invitation sent successfully!"
                        showEmailStatus = true
                        emailSent = true
                        isLoading = false
                        
                        // Auto-dismiss after success
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    
                    // Reload users list
                    await inventoryManager.loadData()
                    
                } catch {
                    print("❌ Failed to invite user: \(error)")
                    
                    await MainActor.run {
                        // Parse different types of errors
                        if error.localizedDescription.contains("email") {
                            showEmailStatus = true
                            emailSent = false
                            emailError = error.localizedDescription
                            manualInviteLink = "https://your-app.com/accept-invitation?token=example"
                            successMessage = "Invitation created but email failed"
                        } else {
                            errorMessage = "Failed to invite user: \(error.localizedDescription)"
                        }
                        isLoading = false
                    }
                }
            }
        }

        

        // Make sure your APIService class has a closing brace }
        // The error suggests there might be a missing closing brace
        
        private func checkEmailConfiguration() {
            Task {
                do {
                    emailConfigured = try await APIService.shared.testEmailConfiguration()
                } catch {
                    emailConfigured = false
                }
            }
        }
    }
// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var api: APIService
    @State private var showingLogoutAlert = false
    
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
                
                // Subscription Section
                Section(header: Text("Subscription")) {
                    HStack {
                        Text("Current Plan")
                        Spacer()
                        Text(api.currentCompany?.subscriptionTier.uppercased() ?? "N/A")
                            .foregroundColor(.purple)
                            .fontWeight(.medium)
                    }
                    
                    if api.currentCompany?.subscriptionTier != "enterprise" {
                        Button(action: {}) {
                            Text("Upgrade Plan")
                                .frame(maxWidth: .infinity)
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
                
                // Features Section
                Section(header: Text("Features")) {
                    FeatureRow(icon: "infinity", title: "Unlimited Inventory Items", isEnabled: true)
                    FeatureRow(icon: "camera.fill", title: "Barcode Scanning", isEnabled: true)
                    FeatureRow(icon: "clock.fill", title: "Activity Tracking", isEnabled: true)
                    FeatureRow(icon: "person.3.fill", title: "Multi-User Support", isEnabled: true)
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
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let isEnabled: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 30)
            
            Text(title)
            
            Spacer()
            
            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
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

