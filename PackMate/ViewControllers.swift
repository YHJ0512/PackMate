import UIKit
import MapKit
import CoreLocation
import AVFoundation

extension UIViewController {
    func showMessage(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }
}

final class TripsViewController: UITableViewController {
    private let store = TripStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PackMate · 내 여행"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                           target: self, action: #selector(addTrip))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"),
                                                          style: .plain, target: self, action: #selector(settings))
        tableView.backgroundColor = .systemGroupedBackground
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        let label = UILabel()
        label.text = store.loadError ?? "오른쪽 + 버튼으로 첫 여행을 등록하세요."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        tableView.backgroundView = store.trips.isEmpty ? label : nil
    }

    @objc private func addTrip() {
        let form = TripFormViewController()
        navigationController?.pushViewController(form, animated: true)
    }

    @objc private func settings() {
        let alert = UIAlertController(title: "Ollama 설정",
            message: "같은 Mac의 시뮬레이터: http://localhost:11434\n실제 아이폰: AI 컴퓨터의 로컬 주소\n끝에 /api/chat을 붙이지 마세요.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "http://컴퓨터이름.local:11434"
            field.text = AISettings.address
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "모델 이름"
            field.text = AISettings.model
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "저장", style: .default) { _ in
            AISettings.address = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            AISettings.model = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        })
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.trips.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let trip = store.trips[indexPath.row]
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd"
        cell.textLabel?.text = trip.name
        cell.detailTextLabel?.text = "\(formatter.string(from: trip.start)) ~ \(formatter.string(from: trip.end))  ·  \(trip.items.filter { $0.packed }.count)/\(trip.items.count) 준비 완료"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(ChecklistViewController(tripID: store.trips[indexPath.row].id), animated: true)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let id = store.trips[indexPath.row].id
        let alert = UIAlertController(title: "여행 삭제", message: "이 여행과 준비물 목록을 삭제할까요?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            do { try self?.store.remove(id: id); self?.viewWillAppear(false) }
            catch { self?.showMessage("저장 오류", error.localizedDescription) }
        })
        present(alert, animated: true)
    }
}

final class TripFormViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    private let nameField = UITextField()
    private let lodgingField = UITextField()
    private let lodgingSearchButton = UIButton(configuration: .tinted())
    private let lodgingSummary = LodgingSummaryView(frame: .zero)
    private let extrasField = UITextField()
    private var selectedLodging: Lodging?
    private var activeSearch: MKLocalSearch?
    private let startPicker = UIDatePicker()
    private let endPicker = UIDatePicker()
    private let typePicker = UIPickerView()
    private let swimSwitch = UISwitch()
    private let hikeSwitch = UISwitch()
    private let campSwitch = UISwitch()
    private let towelSwitch = UISwitch()
    private let dishesSwitch = UISwitch()
    private let requestField = UITextField()
    private let types = ["펜션", "호텔", "캠핑장", "기타"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "여행 등록"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .onDrag
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        configure(nameField, placeholder: "e.g. Gangneung Trip")
        configure(lodgingField, placeholder: "e.g. Skybay Hotel Gyeongpo")
        lodgingField.returnKeyType = .search
        lodgingField.addTarget(self, action: #selector(searchLodging), for: .editingDidEndOnExit)
        lodgingField.addTarget(self, action: #selector(lodgingNameChanged), for: .editingChanged)
        lodgingSearchButton.setTitle("검색", for: .normal)
        lodgingSearchButton.setContentHuggingPriority(.required, for: .horizontal)
        lodgingSearchButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        lodgingSearchButton.addTarget(self, action: #selector(searchLodging), for: .touchUpInside)
        let lodgingRow = UIStackView(arrangedSubviews: [lodgingField, lodgingSearchButton])
        lodgingRow.alignment = .fill
        lodgingRow.spacing = 8
        lodgingSummary.isHidden = true
        lodgingSummary.showError = { [weak self] message in self?.showMessage("숙소 안내", message) }
        configure(extrasField, placeholder: "e.g. Free parking, 2 bottles of water")
        extrasField.accessibilityHint = "예약 안내에서 무료로 제공된다고 확인한 항목을 쉼표로 구분하세요."
        configure(requestField, placeholder: "e.g. Pack light for hiking")
        requestField.returnKeyType = .done
        for picker in [startPicker, endPicker] {
            picker.datePickerMode = .date
            picker.preferredDatePickerStyle = .compact
            picker.locale = Locale(identifier: "ko_KR")
        }
        endPicker.date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        endPicker.minimumDate = startPicker.date
        startPicker.addTarget(self, action: #selector(startChanged), for: .valueChanged)
        typePicker.dataSource = self
        typePicker.delegate = self
        typePicker.heightAnchor.constraint(equalToConstant: 100).isActive = true
        let fields: [(String, UIView)] = [
            ("여행 이름", nameField), ("출발일", startPicker), ("도착일", endPicker),
            ("숙소 유형", typePicker), ("숙소 이름", lodgingRow),
            ("무료 수건 확인", towelSwitch), ("무료 식기 확인", dishesSwitch),
            ("그 외 확인한 무료 제공품 (선택)", extrasField),
            ("물놀이", swimSwitch), ("등산", hikeSwitch), ("캠핑", campSwitch),
            ("추가 요청", requestField)
        ]
        for (title, field) in fields {
            let label = UILabel()
            label.text = title
            label.font = .preferredFont(forTextStyle: .headline)
            if field is UISwitch || field is UIDatePicker {
                let row = UIStackView(arrangedSubviews: [label, field])
                row.axis = .horizontal
                row.alignment = .center
                stack.addArrangedSubview(row)
            } else {
                stack.addArrangedSubview(label)
                stack.addArrangedSubview(field)
                if field === lodgingRow { stack.addArrangedSubview(lodgingSummary) }
            }
        }
        var config = UIButton.Configuration.filled()
        config.title = "기본 체크리스트 만들기"
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(createTrip), for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    private func configure(_ field: UITextField, placeholder: String) {
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.keyboardType = .asciiCapable
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    @objc private func lodgingNameChanged() {
        guard lodgingField.markedTextRange == nil else { return }
        activeSearch?.cancel()
        activeSearch = nil
        lodgingSearchButton.isEnabled = true
        lodgingSearchButton.setTitle("검색", for: .normal)
        guard let lodging = selectedLodging, lodgingField.text != lodging.name else { return }
        selectedLodging = nil
        lodgingSummary.isHidden = true
        clearConfirmedItems()
    }

    @objc private func searchLodging() {
        view.endEditing(true)
        let query = lodgingField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { showMessage("숙소 검색", "숙소 이름이나 주소를 입력하세요."); return }
        guard activeSearch == nil else { return }
        if let lodging = LodgingGuide.lodgingForKnownName(query) {
            showLodgingResults([lodging])
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        activeSearch = search
        lodgingSearchButton.setTitle("검색 중…", for: .normal)
        lodgingSearchButton.isEnabled = false

        Task { [weak self] in
            let response = try? await search.start()
            guard let self = self, self.activeSearch === search else { return }
            self.activeSearch = nil
            self.lodgingSearchButton.isEnabled = true
            self.lodgingSearchButton.setTitle("검색", for: .normal)
            guard self.viewIfLoaded?.window != nil,
                  self.navigationController?.topViewController === self else { return }
            let results = response?.mapItems.compactMap { item -> Lodging? in
                let place = item.placemark
                let coordinates = place.coordinate
                guard CLLocationCoordinate2DIsValid(coordinates) else { return nil }
                let name = item.name ?? query
                let street = [place.thoroughfare, place.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                let address = [place.administrativeArea, place.locality ?? place.subAdministrativeArea, street]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                let location = Lodging.Location(address: address, latitude: coordinates.latitude,
                                                longitude: coordinates.longitude, countryCode: place.isoCountryCode)
                let website = item.url.flatMap { url in ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? url : nil }
                let guide = LodgingGuide.lookup(name: name, address: address, website: website)
                return Lodging(name: name, location: location, website: website, guide: guide)
            } ?? []
            guard !results.isEmpty else {
                self.showLodgingSearchFallback(query: query)
                return
            }
            self.showLodgingResults(results)
        }
    }

    private func showLodgingSearchFallback(query: String) {
        let alert = UIAlertController(title: "숙소를 찾지 못했어요",
                                      message: "Google 지도에서 주소를 확인한 뒤 숙소 입력칸에 도로명 주소를 넣어 다시 검색해 보세요.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "닫기", style: .cancel))
        alert.addAction(UIAlertAction(title: "Google 지도에서 검색", style: .default) { _ in
            var link = URLComponents()
            link.scheme = "https"
            link.host = "www.google.com"
            link.path = "/maps/search/"
            link.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
            if let url = link.url { UIApplication.shared.open(url) }
        })
        present(alert, animated: true)
    }

    private func showLodgingResults(_ results: [Lodging]) {
        let sheet = UIAlertController(title: "숙소 선택", message: "예약한 숙소의 이름과 주소를 확인하세요.", preferredStyle: .actionSheet)
        for lodging in results.prefix(6) {
            let address = lodging.location?.address ?? ""
            let label = address.isEmpty ? lodging.name : "\(lodging.name) · \(address)"
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.selectLodging(lodging)
            })
        }
        sheet.addAction(UIAlertAction(title: "취소", style: .cancel))
        sheet.popoverPresentationController?.sourceView = lodgingSearchButton
        sheet.popoverPresentationController?.sourceRect = lodgingSearchButton.bounds
        present(sheet, animated: true)
    }

    private func selectLodging(_ lodging: Lodging) {
        if let previous = selectedLodging,
           previous.location?.latitude != lodging.location?.latitude ||
            previous.location?.longitude != lodging.location?.longitude {
            clearConfirmedItems()
        }
        selectedLodging = lodging
        lodgingField.text = lodging.name
        lodgingSummary.display(lodging)
        lodgingSummary.isHidden = false
    }

    private func clearConfirmedItems() {
        towelSwitch.isOn = false
        dishesSwitch.isOn = false
        extrasField.text = nil
    }

    @objc private func startChanged() {
        endPicker.minimumDate = startPicker.date
        if endPicker.date < startPicker.date { endPicker.date = startPicker.date }
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { types.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { types[row] }

    @objc private func createTrip() {
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { showMessage("입력 확인", "여행 이름을 입력하세요."); return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startPicker.date)
        let end = calendar.startOfDay(for: endPicker.date)
        guard end >= start else { showMessage("날짜 확인", "도착일은 출발일보다 빠를 수 없습니다."); return }
        let notes = String((requestField.text ?? "").prefix(500))
        var trip = Trip(name: String(name.prefix(60)), start: start, end: end,
                        kind: types[typePicker.selectedRow(inComponent: 0)],
                        swimming: swimSwitch.isOn, hiking: hikeSwitch.isOn,
                        camping: campSwitch.isOn, towelProvided: towelSwitch.isOn,
                        dishesProvided: dishesSwitch.isOn, request: notes)
        let lodgingName = lodgingField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !lodgingName.isEmpty {
            var lodging = selectedLodging.flatMap { $0.name == lodgingName ? $0 : nil }
                ?? Lodging(name: String(lodgingName.prefix(120)))
            lodging.confirmedExtras = (extrasField.text ?? "").prefix(300).split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            trip.lodging = lodging
        }
        trip.items = PackingCatalog.basicItems(for: trip)
        do {
            try TripStore.shared.upsert(trip)
            guard let nav = navigationController else { return }
            // 등록 화면은 스택에서 빼서 뒤로 가면 내 여행으로 돌아갑니다.
            nav.setViewControllers([nav.viewControllers[0], ChecklistViewController(tripID: trip.id)], animated: true)
        } catch { showMessage("저장 오류", error.localizedDescription) }
    }
}

private final class LodgingSummaryView: UIStackView {
    private let addressLabel = UILabel()
    private let mapView = MKMapView()
    private let mapButton = UIButton(configuration: .tinted())
    private let directionsButton = UIButton(configuration: .tinted())
    private let amenitiesLabel = UILabel()
    private let sourceButton = UIButton(configuration: .plain())
    private var lodging: Lodging?
    var showError: ((String) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 8
        for label in [addressLabel, amenitiesLabel] {
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
        }
        let mapHeight = mapView.heightAnchor.constraint(equalToConstant: 180)
        mapHeight.priority = .defaultHigh
        mapHeight.isActive = true
        mapView.layer.cornerRadius = 10
        mapView.clipsToBounds = true
        mapView.isUserInteractionEnabled = false
        mapView.accessibilityLabel = "숙소 위치 지도"
        mapButton.setTitle("숙소 지도 보기", for: .normal)
        mapButton.addTarget(self, action: #selector(openMap), for: .touchUpInside)
        directionsButton.setTitle("자동차 길찾기", for: .normal)
        directionsButton.addTarget(self, action: #selector(openDirections), for: .touchUpInside)
        sourceButton.addTarget(self, action: #selector(openSource), for: .touchUpInside)
        for subview in [addressLabel, mapView, mapButton, directionsButton, amenitiesLabel, sourceButton] {
            addArrangedSubview(subview)
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func display(_ lodging: Lodging, towels: Bool = false, dishes: Bool = false) {
        self.lodging = lodging
        mapView.removeAnnotations(mapView.annotations)
        mapView.isHidden = lodging.location == nil
        mapButton.isHidden = lodging.location == nil
        directionsButton.setTitle("현재 위치에서 자동차 길찾기", for: .normal)
        directionsButton.isHidden = lodging.location == nil
        if let location = lodging.location {
            let coordinate = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )

            let pin = MKPointAnnotation()
            pin.coordinate = coordinate
            pin.title = lodging.name
            mapView.addAnnotation(pin)

            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            )
            mapView.setRegion(region, animated: false)

            addressLabel.text = location.address.isEmpty
                ? lodging.name
                : "\(lodging.name)\n\(location.address)"
        } else {
            addressLabel.text = "\(lodging.name)\n저장된 지도 위치가 없어요."
        }
        var sections: [String] = []

        if let guide = lodging.guide {
            sections.append(
                (["공식 안내의 무료 제공품"]
                 + guide.freeItems.map { "• \($0)" }
                 + [guide.note])
                .joined(separator: "\n")
            )
        } else {
            sections.append("공식 무료 제공 정보가 없어요. 예약 안내나 숙소에 확인하세요.")
        }
        
        
        
        var confirmed = lodging.confirmedExtras
        if towels { confirmed.append("수건") }
        if dishes { confirmed.append("식기") }
        if !confirmed.isEmpty {
            sections.append((["내가 확인한 무료 제공품"] + confirmed.map { "• \($0)" }).joined(separator: "\n"))
        }
        amenitiesLabel.text = sections.joined(separator: "\n\n")
        sourceButton.isHidden = lodging.guide == nil && lodging.website == nil
        sourceButton.setTitle(lodging.guide == nil ? "숙소 웹사이트 열기" : "숙소 공식 안내 보기", for: .normal)
    }

    @objc private func openSource() {
        guard let url = lodging?.guide?.sourceURL ?? lodging?.website else { return }
        UIApplication.shared.open(url)
    }

    @objc private func openMap() {
        showMap(requestRoute: false)
    }

    @objc private func openDirections() {
        showMap(requestRoute: true)
    }

    private func showMap(requestRoute: Bool) {
        guard let lodging = lodging, lodging.location != nil else {
            showError?("숙소의 위치 정보가 없어요. 숙소를 다시 검색해 주세요.")
            return
        }
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                let screen = LodgingMapViewController(lodging: lodging, requestRoute: requestRoute)
                controller.navigationController?.pushViewController(screen, animated: true)
                return
            }
            responder = current.next
        }
    }
}

// 경로 위의 위치를 찾아 회전 지점까지의 거리를 계산합니다.
private struct LodgingRouteGeometry {
    let points: [MKMapPoint]
    let distances: [Double]
    var length: Double { distances.last ?? 0 }

    init(polyline: MKPolyline) {
        points = Array(UnsafeBufferPointer(start: polyline.points(), count: polyline.pointCount))
        var accumulated = [0.0]
        for index in 1..<max(1, points.count) {
            accumulated.append(accumulated[index - 1] + points[index - 1].distance(to: points[index]))
        }
        distances = accumulated
    }

    func project(_ coordinate: CLLocationCoordinate2D, within range: ClosedRange<Double>) -> (progress: Double, distance: Double)? {
        guard points.count > 1 else { return nil }
        let position = MKMapPoint(coordinate)
        var nearest: (progress: Double, distance: Double)?
        for index in 1..<points.count {
            let segmentLength = distances[index] - distances[index - 1]
            guard segmentLength > 0, distances[index] >= range.lowerBound,
                  distances[index - 1] <= range.upperBound else { continue }
            let start = points[index - 1]
            let dx = points[index].x - start.x
            let dy = points[index].y - start.y
            let lower = max(0, (range.lowerBound - distances[index - 1]) / segmentLength)
            let upper = min(1, (range.upperBound - distances[index - 1]) / segmentLength)
            let fraction = min(upper, max(lower, ((position.x - start.x) * dx + (position.y - start.y) * dy) / (dx * dx + dy * dy)))
            let projected = MKMapPoint(x: start.x + dx * fraction, y: start.y + dy * fraction)
            let distance = position.distance(to: projected)
            if distance < (nearest?.distance ?? .greatestFiniteMagnitude) {
                nearest = (distances[index - 1] + segmentLength * fraction, distance)
            }
        }
        return nearest
    }
}

private final class LodgingMapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate, UIGestureRecognizerDelegate {
    private let lodging: Lodging
    private let mapView = MKMapView()
    private let locationManager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private let instructionLabel = UILabel()
    private let statusLabel = UILabel()
    private let stepsLabel = UILabel()
    private let routeButton = UIButton(configuration: .tinted())
    private let navigationButton = UIButton(configuration: .filled())
    private var voiceButton: UIBarButtonItem!
    private var requestRouteOnAppearance: Bool
    private var waitingForLocation = false
    private var startAfterLocation = false
    private var isNavigating = false
    private var followsLocation = true
    private var voiceEnabled = true
    private var locationTimeout: Timer?
    private var locationWatchdog: Timer?
    private var directions: MKDirections?
    private var selectedRoute: MKRoute?
    private var geometry: LodgingRouteGeometry?
    private var maneuvers: [(instruction: String, progress: Double)] = []
    private var routeOrigin: CLLocation?
    private var currentLocation: CLLocation?
    private var progressLocation: CLLocation?
    private var routeProgress = 0.0
    private var spokenPrompts: Set<String> = []
    private var deviationStarted: Date?
    private var deviationSamples = 0
    private var arrivalStarted: Date?
    private var lastRouteRequest = Date.distantPast
    private var previousIdleTimerSetting: Bool?

    init(lodging: Lodging, requestRoute: Bool) {
        self.lodging = lodging
        requestRouteOnAppearance = requestRoute
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var destination: CLLocationCoordinate2D? {
        guard let location = lodging.location else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "숙소 길안내"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        voiceButton = UIBarButtonItem(image: UIImage(systemName: "speaker.wave.2.fill"), style: .plain,
                                      target: self, action: #selector(toggleVoice))
        voiceButton.accessibilityLabel = "음성 안내 끄기"
        let followButton = UIBarButtonItem(image: UIImage(systemName: "location.fill"), style: .plain,
                                           target: self, action: #selector(recenter))
        followButton.accessibilityLabel = "내 위치 따라가기"
        navigationItem.rightBarButtonItems = [followButton, voiceButton]
        mapView.delegate = self
        mapView.accessibilityLabel = "숙소까지의 경로와 현재 위치"
        let pan = UIPanGestureRecognizer(target: self, action: #selector(mapPanned(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        mapView.addGestureRecognizer(pan)
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = 5
        locationManager.pausesLocationUpdatesAutomatically = false
        speech.usesApplicationAudioSession = false

        instructionLabel.font = .preferredFont(forTextStyle: .title2)
        instructionLabel.numberOfLines = 3
        instructionLabel.adjustsFontForContentSizeCategory = true
        instructionLabel.text = "숙소까지의 경로를 검색해 주세요."
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.numberOfLines = 0
        stepsLabel.font = .preferredFont(forTextStyle: .body)
        stepsLabel.numberOfLines = 0
        for label in [statusLabel, stepsLabel] { label.adjustsFontForContentSizeCategory = true }
        routeButton.setTitle("경로 검색", for: .normal)
        routeButton.addTarget(self, action: #selector(findRoute), for: .touchUpInside)
        navigationButton.setTitle("안내 시작", for: .normal)
        navigationButton.addTarget(self, action: #selector(toggleNavigation), for: .touchUpInside)
        navigationButton.isHidden = true
        let buttons = UIStackView(arrangedSubviews: [routeButton, navigationButton])
        buttons.spacing = 10
        buttons.distribution = .fillEqually
        let scroll = UIScrollView()
        scroll.addSubview(stepsLabel)
        stepsLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stepsLabel.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stepsLabel.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stepsLabel.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stepsLabel.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stepsLabel.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        let banner = UIStackView(arrangedSubviews: [instructionLabel])
        banner.isLayoutMarginsRelativeArrangement = true
        banner.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        let details = UIStackView(arrangedSubviews: [statusLabel, buttons, scroll])
        details.axis = .vertical
        details.spacing = 10
        details.isLayoutMarginsRelativeArrangement = true
        details.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        let content = UIStackView(arrangedSubviews: [banner, mapView, details])
        content.axis = .vertical
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: safe.topAnchor),
            content.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            mapView.heightAnchor.constraint(equalTo: content.heightAnchor, multiplier: 0.48)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(appEnteredBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        guard let coordinate = destination else {
            statusLabel.text = "숙소 위치 정보가 올바르지 않아요. 숙소를 다시 검색해 주세요."
            routeButton.isEnabled = false
            return
        }
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        pin.title = lodging.name
        pin.subtitle = lodging.location?.address
        mapView.addAnnotation(pin)
        mapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000), animated: false)
        statusLabel.text = lodging.name
        stepsLabel.text = "경로를 검색한 뒤 안내 시작을 누르세요."
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if requestRouteOnAppearance && routeButton.isEnabled {
            requestRouteOnAppearance = false
            findRoute()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAllRequests()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func appEnteredBackground() {
        stopAllRequests()
        instructionLabel.text = "안내가 종료됐어요."
        statusLabel.text = "안내 시작을 눌러 다시 안내받으세요."
    }

    private func stopAllRequests() {
        stopNavigation()
        waitingForLocation = false
        startAfterLocation = false
        locationTimeout?.invalidate()
        locationTimeout = nil
        let old = directions
        directions = nil
        old?.cancel()
        routeButton.isEnabled = destination != nil
        navigationButton.isEnabled = true
    }

    @objc private func findRoute() {
        guard destination != nil, !waitingForLocation, directions == nil, !isNavigating else { return }
        selectedRoute = nil
        geometry = nil
        navigationButton.isHidden = true
        mapView.removeOverlays(mapView.overlays)
        stepsLabel.text = nil
        acquireLocation(startNavigation: false)
    }

    @objc private func toggleNavigation() {
        if isNavigating {
            stopAllRequests()
            instructionLabel.text = "안내를 종료했어요."
            return
        }
        guard selectedRoute != nil, !waitingForLocation, directions == nil else { return }
        acquireLocation(startNavigation: true)
    }

    private func acquireLocation(startNavigation: Bool) {
        waitingForLocation = true
        startAfterLocation = startNavigation
        routeButton.isEnabled = false
        navigationButton.isEnabled = false
        statusLabel.text = "현재 위치를 확인하고 있어요…"
        locationTimeout?.invalidate()
        locationTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.fail("현재 위치를 확인하지 못했어요. 위치 권한과 시뮬레이터의 위치 설정을 확인해 주세요.")
        }
        checkLocationAuthorization()
    }

    private func checkLocationAuthorization() {
        guard waitingForLocation || isNavigating else { return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            mapView.showsUserLocation = true
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            fail("설정에서 PackMate의 위치 접근을 허용한 뒤 다시 시도해 주세요.")
        @unknown default:
            fail("위치 권한을 확인할 수 없어요.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard waitingForLocation || isNavigating,
              let location = locations.last,
              CLLocationCoordinate2DIsValid(location.coordinate),
              abs(location.timestamp.timeIntervalSinceNow) < 15,
              location.horizontalAccuracy >= 0 else { return }
        guard location.horizontalAccuracy <= 50 else {
            statusLabel.text = "GPS 정확도가 낮아요. 정확한 위치를 기다리고 있어요…"
            return
        }
        currentLocation = location
        if waitingForLocation {
            waitingForLocation = false
            locationTimeout?.invalidate()
            locationTimeout = nil
            if startAfterLocation, let origin = routeOrigin, origin.distance(from: location) < 50 {
                startAfterLocation = false
                beginNavigation(at: location)
            } else {
                calculateRoute(from: location, resumeNavigation: startAfterLocation)
            }
            return
        }
        updateNavigation(at: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard waitingForLocation || isNavigating else { return }
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            statusLabel.text = "GPS 위치를 다시 확인하고 있어요…"
            return
        }
        fail("현재 위치를 확인하지 못했어요.\n\(error.localizedDescription)")
    }

    private func fail(_ message: String) {
        stopAllRequests()
        statusLabel.text = message
    }

    private func calculateRoute(from origin: CLLocation, resumeNavigation: Bool) {
        guard let destination = destination else { fail("숙소 위치가 없어요."); return }
        startAfterLocation = false
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.destination?.name = lodging.name
        request.transportType = .automobile
        let calculation = MKDirections(request: request)
        directions = calculation
        lastRouteRequest = Date()
        routeButton.isEnabled = false
        navigationButton.isEnabled = isNavigating
        statusLabel.text = resumeNavigation ? "경로를 다시 검색하고 있어요…" : "자동차 경로를 검색하고 있어요…"
        calculation.calculate { [weak self, weak calculation] response, error in
            guard let self = self, let calculation = calculation, self.directions === calculation else { return }
            self.directions = nil
            if let error = error {
                self.fail("경로 검색에 실패했어요. 인터넷 연결과 해당 지역의 경로 지원 여부를 확인해 주세요.\n\(error.localizedDescription)")
                return
            }
            guard let route = response?.routes.first else { self.fail("제공되는 자동차 경로가 없어요."); return }
            let geometry = LodgingRouteGeometry(polyline: route.polyline)
            guard geometry.length > 1 else { self.fail("안내할 경로가 없어요. 숙소 근처인지 확인해 주세요."); return }
            self.selectedRoute = route
            self.geometry = geometry
            self.routeOrigin = origin
            self.routeProgress = 0
            self.progressLocation = nil
            self.spokenPrompts.removeAll()
            self.deviationStarted = nil
            self.deviationSamples = 0
            self.arrivalStarted = nil
            let stepDistance = route.steps.reduce(0) { $0 + $1.distance }
            let scale = stepDistance > 0 ? geometry.length / stepDistance : 1
            var travelled = 0.0
            self.maneuvers = route.steps.compactMap { step in
                let progress = travelled
                travelled += step.distance * scale
                guard !step.instructions.isEmpty else { return nil }
                return (step.instructions, progress)
            }
            self.mapView.removeOverlays(self.mapView.overlays)
            self.mapView.addOverlay(route.polyline)
            self.stepsLabel.text = route.steps.filter { !$0.instructions.isEmpty }.map {
                "\($0.instructions) · \(self.distanceText($0.distance))"
            }.joined(separator: "\n\n")
            self.navigationButton.isHidden = false
            self.navigationButton.isEnabled = true
            if resumeNavigation {
                // 재검색 중에 받은 최신 위치로 안내를 이어갑니다.
                if let latest = self.currentLocation, abs(latest.timestamp.timeIntervalSinceNow) < 15 {
                    self.beginNavigation(at: latest)
                } else {
                    self.acquireLocation(startNavigation: true)
                }
            } else {
                self.locationManager.stopUpdatingLocation()
                self.routeButton.isEnabled = true
                self.mapView.setVisibleMapRect(route.polyline.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 40, left: 35, bottom: 40, right: 35), animated: true)
                self.instructionLabel.text = "안내 시작을 누르면 이동에 따라 안내해요."
                self.showRemainingDistance(geometry.length)
            }
        }
    }

    private func beginNavigation(at location: CLLocation) {
        guard selectedRoute != nil else { return }
        let wasNavigating = isNavigating
        if !wasNavigating {
            routeProgress = 0
            progressLocation = nil
            spokenPrompts.removeAll()
            arrivalStarted = nil
            deviationStarted = nil
            deviationSamples = 0
        }
        isNavigating = true
        followsLocation = true
        mapView.showsUserLocation = true
        navigationButton.setTitle("안내 종료", for: .normal)
        navigationButton.isEnabled = true
        routeButton.isEnabled = false
        if previousIdleTimerSetting == nil {
            previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        locationManager.startUpdatingLocation()
        locationWatchdog?.invalidate()
        locationWatchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self, self.isNavigating else { return }
            if Date().timeIntervalSince(self.currentLocation?.timestamp ?? .distantPast) > 15 {
                self.statusLabel.text = "GPS 위치 수신이 지연되고 있어요."
            }
        }
        if !wasNavigating { speak("숙소까지 자동차 안내를 시작합니다.") }
        updateNavigation(at: location)
    }

    private func stopNavigation() {
        isNavigating = false
        locationManager.stopUpdatingLocation()
        mapView.showsUserLocation = false
        locationWatchdog?.invalidate()
        locationWatchdog = nil
        speech.stopSpeaking(at: .immediate)
        if let previous = previousIdleTimerSetting {
            UIApplication.shared.isIdleTimerDisabled = previous
            previousIdleTimerSetting = nil
        }
        navigationButton.setTitle("안내 시작", for: .normal)
    }

    private func updateNavigation(at location: CLLocation) {
        guard isNavigating, let geometry = geometry, directions == nil else { return }
        if followsLocation { follow(location) }
        let elapsed = max(0, location.timestamp.timeIntervalSince(progressLocation?.timestamp ?? location.timestamp))
        let lookAhead = max(200, elapsed * max(30, location.speed) + location.horizontalAccuracy * 2)
        let range = max(0, routeProgress - 30)...min(geometry.length, routeProgress + lookAhead)
        guard let match = geometry.project(location.coordinate, within: range) else { return }
        if match.distance > max(65, location.horizontalAccuracy * 2) {
            arrivalStarted = nil
            deviationSamples += 1
            if deviationStarted == nil { deviationStarted = location.timestamp }
            statusLabel.text = "경로와 현재 위치를 확인하고 있어요…"
            if deviationSamples >= 3, let started = deviationStarted,
               location.timestamp.timeIntervalSince(started) >= 5,
               Date().timeIntervalSince(lastRouteRequest) >= 30 {
                speak("경로를 다시 검색합니다.")
                calculateRoute(from: location, resumeNavigation: true)
            }
            return
        }
        deviationStarted = nil
        deviationSamples = 0
        routeProgress = max(routeProgress, match.progress)
        progressLocation = location
        let remaining = max(0, geometry.length - routeProgress)
        showRemainingDistance(remaining)
        if let endpoint = geometry.points.last {
            let endpointLocation = CLLocation(latitude: endpoint.coordinate.latitude, longitude: endpoint.coordinate.longitude)
            if remaining < 60, location.distance(from: endpointLocation) < 35,
               location.horizontalAccuracy <= 30, location.speed < 3 {
                if arrivalStarted == nil { arrivalStarted = location.timestamp }
                if let started = arrivalStarted, location.timestamp.timeIntervalSince(started) >= 2 {
                    stopAllRequests()
                    instructionLabel.text = "목적지에 도착했어요."
                    statusLabel.text = lodging.name
                    speak("목적지에 도착했습니다.")
                    return
                }
            } else {
                arrivalStarted = nil
            }
        }
        guard let next = maneuvers.enumerated().first(where: { $0.element.progress > routeProgress + 8 }) else {
            instructionLabel.text = "목적지까지 \(distanceText(remaining))"
            announce("숙소 도착 지점까지 \(distanceText(remaining))입니다.", key: "destination", when: remaining <= 100)
            return
        }
        let distance = max(0, next.element.progress - routeProgress)
        instructionLabel.text = "\(distanceText(distance)) 앞\n\(next.element.instruction)"
        let advanceDistance = max(300, max(0, location.speed) * 20)
        announce("\(distanceText(distance)) 앞, \(next.element.instruction)",
                 key: "\(next.offset)-advance", when: distance <= advanceDistance && distance > 60)
        announce("잠시 후, \(next.element.instruction)", key: "\(next.offset)-near", when: distance <= 60)
    }

    private func showRemainingDistance(_ remaining: Double) {
        guard let route = selectedRoute, let geometry = geometry else { return }
        let minutes = max(1, Int(ceil(route.expectedTravelTime * remaining / max(1, geometry.length) / 60)))
        statusLabel.text = "\(lodging.name)까지 \(distanceText(remaining)) · 약 \(minutes)분"
    }

    private func distanceText(_ distance: Double) -> String {
        if distance >= 1000 { return String(format: "%.1f킬로미터", distance / 1000) }
        return "\(max(0, Int(distance.rounded())))미터"
    }

    private func announce(_ text: String, key: String, when condition: Bool) {
        guard condition, voiceEnabled, !speech.isSpeaking, !spokenPrompts.contains(key) else { return }
        spokenPrompts.insert(key)
        speak(text)
    }

    private func speak(_ text: String) {
        guard voiceEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speech.speak(utterance)
    }

    @objc private func toggleVoice() {
        voiceEnabled.toggle()
        if !voiceEnabled { speech.stopSpeaking(at: .immediate) }
        voiceButton.image = UIImage(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
        voiceButton.accessibilityLabel = voiceEnabled ? "음성 안내 끄기" : "음성 안내 켜기"
    }

    @objc private func recenter() {
        followsLocation = true
        if let location = currentLocation { follow(location) }
    }

    private func follow(_ location: CLLocation) {
        let heading = location.course >= 0 && location.speed > 1 ? location.course : mapView.camera.heading
        mapView.setCamera(MKMapCamera(lookingAtCenter: location.coordinate, fromDistance: 650,
                                    pitch: 45, heading: heading), animated: false)
    }

    @objc private func mapPanned(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { followsLocation = false }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = .systemBlue
        renderer.lineWidth = 7
        return renderer
    }
}

final class ChecklistViewController: UITableViewController {
    private let tripID: UUID
    private var task: Task<Void, Never>?
    private var requesting = false
    private let statusLabel = UILabel()
    private var trip: Trip? { TripStore.shared.trip(id: tripID) }

    init(tripID: UUID) {
        self.tripID = tripID
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = trip?.name ?? "준비물"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                           target: self, action: #selector(addItem))
        if trip?.lodging != nil, let addButton = navigationItem.rightBarButtonItem {
            let lodgingButton = UIBarButtonItem(title: "숙소", style: .plain, target: self, action: #selector(showLodging))
            navigationItem.rightBarButtonItems = [addButton, lodgingButton]
        }
        let header = UIStackView()
        header.axis = .vertical
        header.spacing = 12
        header.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        header.isLayoutMarginsRelativeArrangement = true
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        header.addArrangedSubview(statusLabel)
        var config = UIButton.Configuration.filled()
        config.title = "AI 추천 물품 추가"
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(recommend), for: .touchUpInside)
        header.addArrangedSubview(button)
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 155)
        tableView.tableHeaderView = header
        refresh()
    }

    @objc private func showLodging() {
        guard let trip = trip, let lodging = trip.lodging else { return }
        let controller = UIViewController()
        controller.title = "숙소 정보"
        controller.view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(scroll)
        let summary = LodgingSummaryView(frame: .zero)
        summary.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(summary)
        let safeArea = controller.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safeArea.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            summary.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            summary.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            summary.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            summary.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            summary.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        summary.showError = { [weak controller] message in controller?.showMessage("숙소 안내", message) }
        summary.display(lodging, towels: trip.towelProvided, dishes: trip.dishesProvided)
        navigationController?.pushViewController(controller, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 화면을 나가면 남은 요청을 취소합니다. 취소 자체를 오류 팝업으로 표시하지 않습니다.
        if isMovingFromParent { task?.cancel() }
    }

    private func refresh() {
        guard let trip = trip else { return }
        statusLabel.text = "\(trip.source)\n\(trip.items.filter { $0.packed }.count)/\(trip.items.count) 준비 완료 · 행을 누르면 체크\n수량 수정: 행 길게 누르기 / 삭제: 왼쪽 밀기"
        if requesting { statusLabel.text = "AI 추천 요청 중…\n기존 목록은 유지됩니다." }
        tableView.reloadData()
    }

    private func save(_ updated: Trip) {
        do { try TripStore.shared.upsert(updated); refresh() }
        catch { showMessage("저장 오류", error.localizedDescription) }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        trip?.items.count ?? 0
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        guard let item = trip?.items[indexPath.row] else { return cell }
        cell.textLabel?.text = item.name
        cell.detailTextLabel?.text = "\(item.quantity)개"
        cell.accessoryType = item.packed ? .checkmark : .none
        cell.textLabel?.textColor = item.packed ? .secondaryLabel : .label
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard var trip = trip else { return }
        trip.items[indexPath.row].packed.toggle()
        save(trip)
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, var trip = trip else { return }
        trip.items.remove(at: indexPath.row)
        save(trip)
    }

    override func tableView(_ tableView: UITableView,
                            contextMenuConfigurationForRowAt indexPath: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = trip?.items[indexPath.row] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [UIAction(title: "수량 수정", image: UIImage(systemName: "number")) { _ in
                self?.editQuantity(itemID: item.id)
            }])
        }
    }

    private func editQuantity(itemID: UUID) {
        guard let item = trip?.items.first(where: { $0.id == itemID }) else { return }
        let alert = UIAlertController(title: "수량 수정", message: item.name, preferredStyle: .alert)
        alert.addTextField { $0.text = String(item.quantity); $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "저장", style: .default) { [weak self] _ in
            guard let self = self, var trip = self.trip,
                  let index = trip.items.firstIndex(where: { $0.id == itemID }) else { return }
            guard let quantity = Int(alert.textFields?.first?.text ?? ""), (1...99).contains(quantity) else {
                self.showMessage("입력 확인", "수량은 1~99 사이로 입력하세요."); return
            }
            trip.items[index].quantity = quantity
            self.save(trip)
        })
        present(alert, animated: true)
    }

    @objc private func addItem() {
        let alert = UIAlertController(title: "물품 추가", message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "e.g. Phone charger"
            $0.keyboardType = .asciiCapable
            $0.autocorrectionType = .no
        }
        alert.addTextField { $0.placeholder = "수량"; $0.text = "1"; $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "추가", style: .default) { [weak self] _ in
            guard let self = self, var trip = self.trip else { return }
            let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, let quantity = Int(alert.textFields?[1].text ?? ""), (1...99).contains(quantity) else {
                self.showMessage("입력 확인", "물품 이름과 수량(1~99)을 입력하세요."); return
            }
            guard !trip.items.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                self.showMessage("중복 물품", "이미 있는 물품입니다. 길게 눌러 수량을 수정하세요."); return
            }
            trip.items.append(PackingItem(name: String(name.prefix(60)), quantity: quantity))
            self.save(trip)
        })
        present(alert, animated: true)
    }

    @objc private func recommend() {
        guard !requesting, let snapshot = trip else { return }
        requesting = true
        refresh()
        let address = AISettings.address
        let model = AISettings.model
        task = Task { [weak self] in
            do {
                let entries = try await OllamaService.recommend(for: snapshot, address: address, model: model)
                try Task.checkCancellation()
                guard let self = self, var latest = self.trip else { return }
                // 요청 중 사용자가 체크하거나 추가한 내용도 보존합니다.
                var added = 0
                for entry in entries {
                    let exists = latest.items.contains { $0.catalogID == entry.id || $0.name == entry.name }
                    if !exists { latest.items.append(PackingItem(name: entry.name, catalogID: entry.id)); added += 1 }
                }
                latest.source = "기본 목록 + AI 추천 검토 완료"
                self.requesting = false
                try TripStore.shared.upsert(latest)
                self.refresh()
                self.showMessage("AI 추천 완료", "\(added)개 물품을 추가했습니다. 추천은 초안이므로 직접 확인하세요.")
            } catch {
                guard let self = self else { return }
                self.requesting = false
                self.refresh()
                guard !Task.isCancelled else { return }
                self.showMessage("AI 추천 실패", "기존 목록은 유지됩니다.\n\(error.localizedDescription)")
            }
        }
    }
}
