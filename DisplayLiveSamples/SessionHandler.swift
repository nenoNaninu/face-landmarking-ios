//
//  SessionHandler.swift
//  DisplayLiveSamples
//
//  Created by Luis Reisewitz on 15.05.16.
//  Copyright © 2016 ZweiGraf. All rights reserved.
//

import AVFoundation

class SessionHandler : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate {
    var session = AVCaptureSession()
    let layer = AVSampleBufferDisplayLayer()
    let sampleQueue = DispatchQueue(label: "com.zweigraf.DisplayLiveSamples.sampleQueue", attributes: [])
    let faceQueue = DispatchQueue(label: "com.zweigraf.DisplayLiveSamples.faceQueue", attributes: [])
    let wrapper = DlibWrapper()
    
    var currentMetadata: [AnyObject]
    override init() {
        currentMetadata = []
        super.init()
    }
    
    func openSession() {
        let device = AVCaptureDevice.devices(for: AVMediaType.video)
            .map { $0 }
            .filter { $0.position == .front}
            .first!
        
        let input = try! AVCaptureDeviceInput(device: device)
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        
        let metaOutput = AVCaptureMetadataOutput()
        metaOutput.setMetadataObjectsDelegate(self, queue: faceQueue)
    
        session.beginConfiguration()
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        if session.canAddOutput(metaOutput) {
            session.addOutput(metaOutput)
        }
        
        session.commitConfiguration()
        
        let settings: [AnyHashable: Any] = [kCVPixelBufferPixelFormatTypeKey as AnyHashable: Int(kCVPixelFormatType_32BGRA)]
        output.videoSettings = settings as! [String : Any]
        
        /***************************************************************************/
        //fpsをあげるためのルーチン
        var minFPS = 0.0
        var maxFPS = 0.0
        var maxWidth:Int32 = 0
        var selectedFormat:AVCaptureDevice.Format? = nil
        for format in (device.formats){
            for range in format.videoSupportedFrameRateRanges{
                let desc = format.formatDescription
                let dimentions = CMVideoFormatDescriptionGetDimensions(desc)
                
                if(minFPS <= range.minFrameRate && maxFPS <= range.maxFrameRate && maxWidth <= dimentions.width){
                    minFPS = range.minFrameRate
                    maxFPS = range.maxFrameRate
                    maxWidth = dimentions.width
                    selectedFormat = format
                }
            }
        }
        
        do{
            try device.lockForConfiguration()
            device.activeFormat = selectedFormat!
            device.activeVideoMinFrameDuration = CMTimeMake(1,Int32(minFPS))
            device.activeVideoMaxFrameDuration = CMTimeMake(1,Int32(maxFPS))
            device.unlockForConfiguration()
        }catch{
            
        }
        
        /***************************************************************************/
    
        // availableMetadataObjectTypes change when output is added to session.
        // before it is added, availableMetadataObjectTypes is empty
        metaOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.face]
        
        wrapper?.prepare()
        
        session.startRunning()
    }
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        if !currentMetadata.isEmpty {
            let boundsArray = currentMetadata
                .compactMap { $0 as? AVMetadataFaceObject }//ダウンキャストできないとnilが帰ってくる->nilはmapが弾いてくれる。
                .map { (faceObject) -> NSValue in
                    let convertedObject = output.transformedMetadataObject(for: faceObject, connection: connection)
                    return NSValue(cgRect: convertedObject!.bounds)
                }
            
            wrapper?.doWork(on: sampleBuffer, inRects: boundsArray)
        }

        layer.enqueue(sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("DidDropSampleBuffer")
    }
    
    // MARK: AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        currentMetadata = metadataObjects as [AnyObject]
        print(currentMetadata)
    }
}
