/*
* Copyright (c) 2010-2020 Belledonne Communications SARL.
*
* This file is part of linphone-iphone
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

import Foundation
import CallKit
import UIKit
import linphonesw
import AVFoundation
import os

@objc class CallInfo: NSObject {
	var callId: String = ""
	var accepted = false
	var toAddr: Address?
	var isOutgoing = false
	var sasEnabled = false
	var declined = false
	var connected = false
	
	
	static func newIncomingCallInfo(callId: String) -> CallInfo {
		let callInfo = CallInfo()
		callInfo.callId = callId
		return callInfo
	}
	
	static func newOutgoingCallInfo(addr: Address, isSas: Bool) -> CallInfo {
		let callInfo = CallInfo()
		callInfo.isOutgoing = true
		callInfo.sasEnabled = isSas
		callInfo.toAddr = addr
		return callInfo
	}
}

/*
* A delegate to support callkit.
*/
class ProviderDelegate: NSObject {
	private let provider: CXProvider
	var uuids: [String : UUID] = [:]
	var callInfos: [UUID : CallInfo] = [:]

	override init() {
		provider = CXProvider(configuration: ProviderDelegate.providerConfiguration)
		super.init()
		provider.setDelegate(self, queue: nil)
	}

    static var providerConfiguration: CXProviderConfiguration = {
        let providerConfiguration = CXProviderConfiguration(localizedName: Bundle.main.infoDictionary!["CFBundleName"] as! String)
        providerConfiguration.ringtoneSound = "peek_door_quest.caf"
        providerConfiguration.supportsVideo = true
        providerConfiguration.iconTemplateImageData = UIImage(named: "callkit_logo")?.pngData()
        providerConfiguration.supportedHandleTypes = [.generic]

        providerConfiguration.maximumCallsPerCallGroup = 10
        providerConfiguration.maximumCallGroups = 2

        //not show app's calls in tel's history
        //providerConfiguration.includesCallsInRecents = YES;
        
        return providerConfiguration
    }()

    static var providerConfigurationSilent: CXProviderConfiguration = {
        let providerConfiguration = CXProviderConfiguration(localizedName: Bundle.main.infoDictionary!["CFBundleName"] as! String)
        providerConfiguration.ringtoneSound = "shhht.caf"
        providerConfiguration.supportsVideo = false
        providerConfiguration.iconTemplateImageData = nil
        providerConfiguration.supportedHandleTypes = [.generic]
        if #available(iOS 11.0, *) {
            providerConfiguration.includesCallsInRecents = false
        }
        providerConfiguration.maximumCallsPerCallGroup = 0
        providerConfiguration.maximumCallGroups = 0

        //not show app's calls in tel's history
        //providerConfiguration.includesCallsInRecents = YES;
        
        return providerConfiguration
    }()

    func reportIncomingCall(call:Call?, uuid: UUID, handle: String, hasVideo: Bool, shouldBeSilent: Bool = false) {
		let update = CXCallUpdate()
		update.remoteHandle = CXHandle(type:.generic, value: handle)
		update.hasVideo = hasVideo
        
        if shouldBeSilent {
            update.supportsHolding = false
            update.supportsGrouping = false
            update.supportsUngrouping = false
            update.supportsDTMF = false
            update.hasVideo = false
            provider.configuration = ProviderDelegate.providerConfigurationSilent
        } else {
            provider.configuration = ProviderDelegate.providerConfiguration
        }

		let callInfo = callInfos[uuid]
		let callId = callInfo?.callId
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: report new incoming call with call-id: [\(String(describing: callId))] and UUID: [\(uuid.description)]")
		provider.reportNewIncomingCall(with: uuid, update: update) { error in
			if error == nil {
				CallManager.instance().providerDelegate.endCallNotExist(uuid: uuid, timeout: .now() + 20)
			} else {
				Log.directLog(BCTBX_LOG_ERROR, text: "CallKit: cannot complete incoming call with call-id: [\(String(describing: callId))] and UUID: [\(uuid.description)] from [\(handle)] caused by [\(error!.localizedDescription)]")
				if (call == nil) {
					callInfo?.declined = true
					self.callInfos.updateValue(callInfo!, forKey: uuid)
					return
				}
				let code = (error as NSError?)?.code
				if code == CXErrorCodeIncomingCallError.filteredByBlockList.rawValue || code == CXErrorCodeIncomingCallError.filteredByDoNotDisturb.rawValue {
                    try? call?.decline(reason: Reason.Busy)
				} else {
                    try? call?.decline(reason: Reason.Unknown)
				}
			}
		}
	}

	func updateCall(uuid: UUID, handle: String, hasVideo: Bool = false) {
		let update = CXCallUpdate()
		update.remoteHandle = CXHandle(type:.generic, value:handle)
		update.hasVideo = hasVideo
		provider.reportCall(with:uuid, updated:update);
	}

	func reportOutgoingCallStartedConnecting(uuid:UUID) {
		provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
	}

	func reportOutgoingCallConnected(uuid:UUID) {
		provider.reportOutgoingCall(with: uuid, connectedAt: nil)
	}
	
	func endCall(uuid: UUID) {
		provider.reportCall(with: uuid, endedAt: .init(), reason: .declinedElsewhere)
	}

	func endCallNotExist(uuid: UUID, timeout: DispatchTime) {
		DispatchQueue.main.asyncAfter(deadline: timeout) {
			let callId = CallManager.instance().providerDelegate.callInfos[uuid]?.callId
			let call = CallManager.instance().callByCallId(callId: callId)
			if (call == nil) {
				Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: terminate call with call-id: \(String(describing: callId)) and UUID: \(uuid) which does not exist.")
				CallManager.instance().providerDelegate.endCall(uuid: uuid)
			}
		}
	}
}

// MARK: - CXProviderDelegate
extension ProviderDelegate: CXProviderDelegate {
	func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
		action.fulfill()
		let uuid = action.callUUID
		let callId = callInfos[uuid]?.callId

		// remove call infos first, otherwise CXEndCallAction will be called more than onece
		if (callId != nil) {
			uuids.removeValue(forKey: callId!)
		}
		callInfos.removeValue(forKey: uuid)

		let call = CallManager.instance().callByCallId(callId: callId)
		if let call = call {
			CallManager.instance().terminateCall(call: call.getCobject);
			Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: Call ended with call-id: \(String(describing: callId)) an UUID: \(uuid.description).")
		}
	}

	func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
		let uuid = action.callUUID
		let callInfo = callInfos[uuid]
		let callId = callInfo?.callId
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: answer call with call-id: \(String(describing: callId)) and UUID: \(uuid.description).")

		let call = CallManager.instance().callByCallId(callId: callId)
		if (call == nil || call?.state != Call.State.IncomingReceived) {
			// The application is not yet registered or the call is not yet received, mark the call as accepted. The audio session must be configured here.
			CallManager.configAudioSession(audioSession: AVAudioSession.sharedInstance())
			callInfo?.accepted = true
			callInfos.updateValue(callInfo!, forKey: uuid)
			CallManager.instance().providerDelegate.endCallNotExist(uuid: uuid, timeout: .now() + 10)
		} else {
			CallManager.instance().acceptCall(call: call!, hasVideo: call!.params?.videoEnabled ?? false)
		}
		action.fulfill()
	}

	func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
		let uuid = action.callUUID
		let callId = callInfos[uuid]?.callId
		let call = CallManager.instance().callByCallId(callId: callId)
		action.fulfill()
		if (call == nil) {
			return
		}

		do {
			if (CallManager.instance().lc?.isInConference ?? false && action.isOnHold) {
				try CallManager.instance().lc?.leaveConference()
				Log.directLog(BCTBX_LOG_DEBUG, text: "CallKit: Leaving conference")
				NotificationCenter.default.post(name: Notification.Name("LinphoneCallUpdate"), object: self)
				return
			}

			let state = action.isOnHold ? "Paused" : "Resumed"
			Log.directLog(BCTBX_LOG_DEBUG, text: "CallKit: Call  with call-id: [\(String(describing: callId))] and UUID: [\(uuid)] paused status changed to: [\(state)]")
			if (action.isOnHold) {
				if (call!.params?.localConferenceMode ?? false) {
					return
				}
				CallManager.instance().speakerBeforePause = CallManager.instance().speakerEnabled
				try call!.pause()
			} else {
				if (CallManager.instance().lc?.conference != nil && CallManager.instance().lc?.callsNb ?? 0 > 1) {
					try CallManager.instance().lc?.enterConference()
					NotificationCenter.default.post(name: Notification.Name("LinphoneCallUpdate"), object: self)
				} else {
					try call!.resume()
				}
			}
		} catch {
			Log.directLog(BCTBX_LOG_ERROR, text: "CallKit: Call set held (paused or resumed) \(uuid) failed because \(error)")
		}
	}

	func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
		do {
			let uuid = action.callUUID
			let callInfo = callInfos[uuid]
			let addr = callInfo?.toAddr
			if (addr == nil) {
				Log.directLog(BCTBX_LOG_ERROR, text: "CallKit: can not call a null address!")
				action.fail()
			}

			try CallManager.instance().doCall(addr: addr!, isSas: callInfo?.sasEnabled ?? false)
		} catch {
			Log.directLog(BCTBX_LOG_ERROR, text: "CallKit: Call started failed because \(error)")
			action.fail()
		}
		action.fulfill()
	}

	func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: Call grouped callUUid : \(action.callUUID) with callUUID: \(String(describing: action.callUUIDToGroupWith)).")
		do {
			try CallManager.instance().lc?.addAllToConference()
		} catch {
			Log.directLog(BCTBX_LOG_ERROR, text: "CallKit: Call grouped failed because \(error)")
		}
		action.fulfill()
	}

	func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
		let uuid = action.callUUID
		let callId = callInfos[uuid]?.callId
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: Call muted with call-id: \(String(describing: callId)) an UUID: \(uuid.description).")
		CallManager.instance().lc!.micEnabled = !CallManager.instance().lc!.micEnabled
		action.fulfill()
	}

	func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
		let uuid = action.callUUID
		let callId = callInfos[uuid]?.callId
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: Call send dtmf with call-id: \(String(describing: callId)) an UUID: \(uuid.description).")
		let call = CallManager.instance().callByCallId(callId: callId)
		if (call != nil) {
			let digit = (action.digits.cString(using: String.Encoding.utf8)?[0])!
			do {
				try call!.sendDtmf(dtmf: digit)
			} catch {
				Log.directLog(BCTBX_LOG_ERROR, text: "CallKit: Call send dtmf \(uuid) failed because \(error)")
			}
		}
		action.fulfill()
	}

	func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
		let uuid = action.uuid
		let callId = callInfos[uuid]?.callId
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: Call time out with call-id: \(String(describing: callId)) an UUID: \(uuid.description).")
		action.fulfill()
	}

	func providerDidReset(_ provider: CXProvider) {
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: did reset.")
	}

	func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: audio session activated.")
		CallManager.instance().lc?.activateAudioSession(actived: true)
	}

	func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
		Log.directLog(BCTBX_LOG_MESSAGE, text: "CallKit: audio session deactivated.")
		CallManager.instance().lc?.activateAudioSession(actived: false)
	}
}

