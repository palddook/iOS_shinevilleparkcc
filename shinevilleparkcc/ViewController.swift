//
//  ViewController.swift
//  shinevilleparkcc
//

import UIKit
import WebKit

// MARK: - 메인/팝업 공통 웹뷰 화면

/// 메인 화면과 팝업 화면이 함께 쓰는 웹뷰 처리.
/// 사이트가 window.open + form target(본인인증 등)과 window.opener 를 쓰므로
/// 팝업은 같은 웹뷰에서 열지 않고 별도 웹뷰(새 창)로 연다.
class BaseWebViewController: UIViewController {

    var webView: WKWebView!

    func makeWebView(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: guide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: guide.trailingAnchor)
        ])
    }

    func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        return config
    }

    // 하위 클래스에서 재정의
    func loadingDidStart() {}
    func loadingDidFinish() {}
    func loadingDidFail(_ error: Error) {}

    fileprivate func topMostViewController() -> UIViewController? {
        var top = view.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    fileprivate func openExternally(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

// MARK: - WKNavigationDelegate

extension BaseWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // 웹뷰가 처리할 수 없는 스킴(전화, 문자, 메일, 앱스토어 등)은 시스템에 넘긴다.
        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "file", "blob", "data", "javascript"].contains(scheme) {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingDidStart()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingDidFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportLoadError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func reportLoadError(_ error: Error) {
        let nsError = error as NSError
        // 사용자가 다른 페이지로 이동하며 취소된 요청은 무시한다.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        // 외부 앱으로 넘기며 중단된 이동(Frame load interrupted)도 무시한다.
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        loadingDidFail(error)
    }
}

// MARK: - WKUIDelegate

extension BaseWebViewController: WKUIDelegate {

    // window.open / target="_blank" 은 새 웹뷰(팝업 화면)로 연다.
    // 전달받은 configuration 으로 웹뷰를 만들어야 window.opener, 창 이름(form target)이 유지된다.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = PopupViewController(configuration: configuration)
        let nav = UINavigationController(rootViewController: popup)
        nav.modalPresentationStyle = .fullScreen
        topMostViewController()?.present(nav, animated: true)
        return popup.webView
    }

    // window.close()
    func webViewDidClose(_ webView: WKWebView) {
        (self as? PopupViewController)?.closePopup()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler() })
        present(alert, on: topMostViewController(), fallback: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler(true) })
        present(alert, on: topMostViewController(), fallback: { completionHandler(false) })
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        present(alert, on: topMostViewController(), fallback: { completionHandler(nil) })
    }

    // 표시할 화면이 없으면 JS 가 멈추지 않도록 기본값으로 응답한다.
    private func present(_ alert: UIAlertController, on presenter: UIViewController?, fallback: () -> Void) {
        guard let presenter = presenter else {
            fallback()
            return
        }
        presenter.present(alert, animated: true)
    }
}

// MARK: - 팝업 화면

final class PopupViewController: BaseWebViewController {

    init(configuration: WKWebViewConfiguration) {
        super.init(nibName: nil, bundle: nil)
        // createWebViewWith 에서 웹뷰를 바로 돌려줘야 하므로 여기서 미리 만든다.
        loadViewIfNeeded()
        makeWebView(configuration: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "닫기", style: .done,
                                                            target: self, action: #selector(closeTapped))
    }

    override func loadingDidFinish() {
        if let title = webView.title, !title.isEmpty {
            navigationItem.title = title
        }
    }

    @objc private func closeTapped() {
        closePopup()
    }

    func closePopup() {
        guard presentingViewController != nil || navigationController?.presentingViewController != nil else { return }
        (navigationController ?? self).dismiss(animated: true)
    }
}

// MARK: - 메인 화면

class ViewController: BaseWebViewController {

    // 홈(/)은 UA 문자열로 모바일 여부를 판단해 /mobile/ 로 보내는데,
    // 최신 iPad 는 PC 로 인식되므로 모바일 주소를 직접 연다.
    private let homeURL = "https://www.shinevilleparkcc.com/mobile/"

    private let indicator = UIActivityIndicatorView(style: .large)
    private let errorView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        makeWebView(configuration: makeConfiguration())
        setupIndicator()
        setupErrorView()
        loadHome()
    }

    // MARK: - Setup

    private func setupIndicator() {
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupErrorView() {
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.backgroundColor = .white
        errorView.isHidden = true

        let label = UILabel()
        label.text = "네트워크 연결을 확인해 주세요."
        label.textColor = .darkGray
        label.textAlignment = .center
        label.numberOfLines = 0

        let button = UIButton(type: .system)
        button.setTitle("다시 시도", for: .normal)
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        errorView.addSubview(stack)
        view.addSubview(errorView)

        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: errorView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: errorView.trailingAnchor, constant: -24)
        ])
    }

    // MARK: - Loading

    private func loadHome() {
        guard let url = URL(string: homeURL) else { return }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20))
    }

    @objc private func retryTapped() {
        errorView.isHidden = true
        if webView.url != nil {
            webView.reload()
        } else {
            loadHome()
        }
    }

    override func loadingDidStart() {
        indicator.startAnimating()
    }

    override func loadingDidFinish() {
        indicator.stopAnimating()
        errorView.isHidden = true
    }

    override func loadingDidFail(_ error: Error) {
        indicator.stopAnimating()
        errorView.isHidden = false
    }
}
