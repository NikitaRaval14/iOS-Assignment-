//
//  ImageGridViewController.swift
//  iOS Assignment
//
//  Created by Nikita on 12/05/24.
//

import UIKit
//MARK: Memory Caching singlton
class MemoryCacheManager
{
    static let shared = MemoryCacheManager()
    private let cacheObj = NSCache<NSString, UIImage>()
    
    //Set image in memory cache
    func setImage(_ image: UIImage, forKey key: String) {
        cacheObj.setObject(image, forKey: key as NSString)
    }
    //Retrieve from memory cache
    func getImage(forKey key: String) -> UIImage? {
        return cacheObj.object(forKey: key as NSString)
    }
}
//MARK: Main Class
class ImageGridViewController: UICollectionViewController {
    
    let apiURL = "https://acharyaprashant.org/api/v2/content/misc/media-coverages?limit=100"
    
    private var imageURLs: [URL] = []
    let memoryCache = MemoryCacheManager.shared
    private let fileManager = FileManager.default
    private lazy var diskCacheDirectory: URL = {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDirectory = paths[0].appendingPathComponent("ImageCache")
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        return cacheDirectory
    }()
    
    //CollectionView
    private let cellIdentifier = "ImageCell"
    private let itemsPerRow: CGFloat = 3
    private let spacing: CGFloat = 8
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        self.setupCollectionView()
        self.fetchMediaCoverages()
    }
    
    //MARK: Set the Collection view
    private func setupCollectionView() {
        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: cellIdentifier)
        collectionView.backgroundColor = .white
        collectionView.delegate = self
    }
    
    //MARK: API Calling
    private func fetchMediaCoverages()
    {
        guard let url = URL(string: apiURL) else {
            print("Invalid API URL")
            return
        }
        let task = URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
            guard let data = data, error == nil else {
                print("Failed to fetch image URLs: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                print("Invalid response")
                return
            }
            do 
            {
                let decoder = JSONDecoder()
                let mediaCoverages = try decoder.decode([MediaCoverage].self, from: data)
                for coverage in mediaCoverages
                {
                    self?.imageURLs.append(URL(string:coverage.thumbnail.constructImageURL())!)
                }
                DispatchQueue.main.async
                {
                    self?.collectionView.reloadData()
                }
            } catch {
                print("Error decoding JSON: \(error.localizedDescription)")
            }
        }
        task.resume()
    }
    
    private func loadImage(from url: URL,indexVal : Int, completion: @escaping (UIImage?) -> Void) {
        // Check memory cache
        if let cachedImage = memoryCache.getImage(forKey: url.absoluteString)
        {
            completion(cachedImage)
            return
        }
        
        // Check Disk cache
        if let cachedImage = loadImageFromDiskCache(withURL: url, indexVal: indexVal) {
            memoryCache.setImage(cachedImage, forKey: url.absoluteString)
            completion(cachedImage)
            return
        }
       
        // If not cached, download the image
        let task = URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
            guard let data = data, let image = UIImage(data: data), error == nil else {
                print("Failed to load image: \(error?.localizedDescription ?? "Unknown error")")
                completion(UIImage(named: "default_image"))
                return
            }
            let cropImg = self?.centerCrop(image)//center crop the image
            // Store in Disk cache
            self!.saveImageToDiskCache(cropImg ?? image, withURL: url, indexVal: indexVal)
            // Store in memory cache
            self!.memoryCache.setImage(cropImg ?? image, forKey: url.absoluteString)
            
            completion(image)
        }
        task.resume()
    }
    //MARK: Center Crop the Image
    private func centerCrop(_ image: UIImage) -> UIImage
    {
        let cgImage = image.cgImage!
        let shorSide = min(image.size.width, image.size.height)
        let cropRect = CGRect(x: (image.size.width - shorSide) / 2, y: (image.size.height - shorSide) / 2, width: shorSide, height: shorSide)
        if let croppedImage = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: croppedImage, scale: image.scale, orientation: image.imageOrientation)
        } else {
            return image // Return original image if cropping fails
        }
    }
    //MARK: Save Image To Disk Cache
    private func saveImageToDiskCache(_ image: UIImage, withURL url: URL,  indexVal : Int) {
        let namingImage = createImageUniqName(url: url, indexVal: indexVal)
        let filePath = diskCacheDirectory.appendingPathComponent(namingImage)
        if let data = image.jpegData(compressionQuality: 1.0) {
            try? data.write(to: filePath)
        }
    }
    //MARK: Load Image To Disk Cache
    private func loadImageFromDiskCache(withURL url: URL , indexVal : Int) -> UIImage? {
        let namingImage = createImageUniqName(url: url, indexVal: indexVal)
        let filePath = diskCacheDirectory.appendingPathComponent(namingImage)
        guard let data = try? Data(contentsOf: filePath) else { return nil }
        return UIImage(data: data)
    }
    //Create Unique name for image to store in memory and caches as All the image have same name and same name images can't be store as it over-write the same named image. So, to make it unique i had defiend named with index path append.
    func createImageUniqName(url: URL , indexVal : Int) -> String
    {
        return NSString(format: "img_%d_%@",indexVal,url.lastPathComponent) as String
    }
    
}
//Struct for Response
struct MediaCoverage: Codable {
    let id: String
    let title: String
    let language: String
    let thumbnail: Thumbnail
}

struct Thumbnail: Codable {
    let id: String
    let version: Int
    let domain: String
    let basePath: String
    let key: String
    let qualities: [Int]
    let aspectRatio: Double
    
    func constructImageURL() -> String {
        return "\(domain)/\(basePath)/0/\(key)"
    }
}
//MARK: UICollectionview Delegate & Data Source
extension ImageGridViewController: UICollectionViewDelegateFlowLayout
{
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageURLs.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as! ImageCell
        let imageURL = imageURLs[indexPath.item]
        cell.imageView.image = nil // Clear previous image
        loadImage(from: imageURL , indexVal : indexPath.item) { image in
            DispatchQueue.main.async {
               cell.imageView.image = image
            }
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let paddingSpace = spacing * (itemsPerRow - 1)
        let availableWidth = UIScreen.main.bounds.width - paddingSpace - 1
        let widthPerItem = availableWidth / itemsPerRow
        return CGSize(width: widthPerItem, height: widthPerItem)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return spacing
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return spacing
    }
}
//MARK: Cell for Collectionview with Imageview
class ImageCell: UICollectionViewCell {
    let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupImageView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupImageView() {
        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

