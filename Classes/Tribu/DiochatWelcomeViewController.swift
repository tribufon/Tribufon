//
//  TribuWelcomeViewController.swift
//  ChatSecureCore
//
//  Created by Lyubomir Marinov on 29.12.19.
//

import UIKit
import MaterialComponents
import QRCodeReaderViewController

class TribuWelcomeViewController: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var nameTextField: MDCTextField!
    @IBOutlet weak var passwordTextField: MDCTextField!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var qrButton: UIButton!
    @IBOutlet weak var qrScanLabel: UILabel!
    
    @IBOutlet var bottomConstraint: NSLayoutConstraint!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    fileprivate let placeholderColor = UIColor.init(white: 200.0/255.0, alpha: 0.8)

    fileprivate let deviceIdKey = "lezilezibubulezi"

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let placeholderAttributes = [
            NSAttributedString.Key.foregroundColor: placeholderColor,
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17)
        ]
        self.nameTextField.attributedPlaceholder = NSAttributedString(string: "Username", attributes: placeholderAttributes)
        self.nameTextField.textColor = .white
        self.nameTextField.placeholderLabel.textColor = placeholderColor
        self.nameTextField.tag = 1
        self.nameTextField.returnKeyType = .next
        self.nameTextField.enablesReturnKeyAutomatically = true
        self.nameTextField.delegate = self
        self.nameTextField.keyboardType = .emailAddress
        
        self.passwordTextField.attributedPlaceholder = NSAttributedString(string: "Password", attributes: placeholderAttributes)
        self.passwordTextField.textColor = .white
        self.passwordTextField.placeholderLabel.textColor = placeholderColor
        self.passwordTextField.tag = 2
        self.passwordTextField.returnKeyType = .go
        self.passwordTextField.enablesReturnKeyAutomatically = true
        self.passwordTextField.delegate = self

        self.qrScanLabel.textAlignment = .center;
        self.qrScanLabel.textColor = UIColor.white
        self.qrScanLabel.font = UIFont.boldSystemFont(ofSize: 13.0)
        self.qrScanLabel.text = "Scan QR"
        
        self.loginButton.addTarget(self, action: #selector(loginAction), for: .touchUpInside)
        
        self.qrButton.addTarget(self, action: #selector(qrCodeScan), for: .touchUpInside)
            
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name:UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name:UIResponder.keyboardWillHideNotification, object: nil)
        }
        
        override open func viewWillAppear(_ animated: Bool) {
            self.navigationController?.setNavigationBarHidden(true, animated: animated)
        }
        
        @objc func keyboardWillShow(notification:NSNotification){

            let userInfo = notification.userInfo!
            var keyboardFrame:CGRect = (userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as! NSValue).cgRectValue
            keyboardFrame = self.view.convert(keyboardFrame, from: nil)
            
            bottomConstraint.constant = keyboardFrame.size.height
        }

        @objc func keyboardWillHide(notification:NSNotification){
            bottomConstraint.constant = 0
        }
    
    @objc private func loginAction() {
        processFormLogin(self.nameTextField.text, password: self.passwordTextField.text)
    }
    
    @objc private func qrCodeScan() {
        if QRCodeReader.supportsMetadataObjectTypes([AVMetadataObject.ObjectType.qr]) {
            var qrViewController: QRCodeReaderViewController?
            
            let reader = QRCodeReader.init(metadataObjectTypes: [AVMetadataObject.ObjectType.qr])
            qrViewController = QRCodeReaderViewController(cancelButtonTitle: "Close",
                                                          codeReader: reader,
                                                          startScanningAtLoad: true,
                                                          showSwitchCameraButton: false,
                                                          showTorchButton: false)
            qrViewController?.delegate = self
            qrViewController?.modalPresentationStyle = .overFullScreen
            
            if qrViewController != nil {
                self.present(qrViewController!, animated: true, completion: nil)
            }
        } else {
            let alert = UIAlertController(title: "Error", message: "QR Reader not supported by current device", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    private func processQRLogin(_ value: String?) {
        guard let _value = value,
            let components = _value.removingPercentEncoding?.components(separatedBy: ":"),
            components.count >= 3 else { return }
        let username = components[1].appending("@sip.tribu.monster")
        let password = components[2].replacingOccurrences(of: "@Tribu", with: "")
            .replacingOccurrences(of: "@TRIBU", with: "")
            .replacingOccurrences(of: "*", with: "")
        
        processFormLogin(username, password: password)
    }
    
    private func processFormLogin(_ username: String?, password: String?) {
        guard let _username = username,
            !_username.isEmpty,
            let _password = password,
            !_password.isEmpty else { return }
        
        print("{\"username\": \(_username), \"password\": \(_password) }")
    }
}

extension TribuWelcomeViewController {
    override func textFieldDidBeginEditing(_ textField: UITextField) {
        super.textFieldDidBeginEditing(textField)
        if let clearButton = textField.value(forKey: "_clearButton") as? UIButton {
            if let templateImage = clearButton.imageView?.image?.withRenderingMode(.alwaysTemplate) {
                clearButton.setImage(templateImage, for: .normal)
                clearButton.tintColor = placeholderColor
            }
        }
    }
    
    override func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let nextTag = textField.tag + 1
        // Try to find next responder
        let nextResponder = textField.superview?.viewWithTag(nextTag) as? UIResponder

        if nextResponder != nil {
            // Found next responder, so set it
            nextResponder?.becomeFirstResponder()
        } else {
            // Not found, so remove keyboard
            textField.resignFirstResponder()
        }

        return false
    }
}

extension TribuWelcomeViewController: QRCodeReaderDelegate {
    func reader(_ reader: QRCodeReaderViewController!, didScanResult result: String!) {
        reader.stopScanning()
        reader.dismiss(animated: true, completion: nil)
        
        processQRLogin(result)
    }
    
    func readerDidCancel(_ reader: QRCodeReaderViewController!) {
        reader.dismiss(animated: true, completion: nil)
    }
}
