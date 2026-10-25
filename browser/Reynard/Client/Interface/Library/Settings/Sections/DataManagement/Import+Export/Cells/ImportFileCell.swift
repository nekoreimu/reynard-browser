//
//  ImportFileCell.swift
//  Reynard
//
//  Created by Minh Ton on 22/10/26.
//

import QuickLookThumbnailing
import UIKit

final class ImportFileCell: UITableViewCell {
    private enum UX {
        static let iconSize: CGFloat = 44
        static let iconVerticalInset: CGFloat = 8
        static let labelsSpacing: CGFloat = 4
        static let labelsLeadingSpacing: CGFloat = 13
        static let labelsVerticalInset: CGFloat = 13
        static let thumbnailSize = CGSize(width: 56, height: 56)
    }
    
    static let reuseIdentifier = "ImportFileCell"
    
    private let fileIconView = UIImageView()
    private let fileNameLabel = UILabel()
    private let sizeLabel = UILabel()
    private var thumbnailRequest: QLThumbnailGenerator.Request?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureViews()
        installViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        if let thumbnailRequest {
            QLThumbnailGenerator.shared.cancel(thumbnailRequest)
        }
        thumbnailRequest = nil
        fileIconView.image = nil
    }
    
    private func configureViews() {
        selectionStyle = .none
        fileIconView.contentMode = .scaleAspectFit
        
        fileNameLabel.font = .preferredFont(forTextStyle: .body)
        fileNameLabel.adjustsFontForContentSizeCategory = true
        
        sizeLabel.font = .preferredFont(forTextStyle: .subheadline)
        sizeLabel.adjustsFontForContentSizeCategory = true
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.numberOfLines = 2
    }
    
    private func installViews() {
        let labelsStack = UIStackView(arrangedSubviews: [fileNameLabel, sizeLabel])
        labelsStack.axis = .vertical
        labelsStack.spacing = UX.labelsSpacing
        fileIconView.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fileIconView)
        contentView.addSubview(labelsStack)
        
        NSLayoutConstraint.activate([
            fileIconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            fileIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileIconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: UX.iconVerticalInset),
            fileIconView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -UX.iconVerticalInset),
            fileIconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            fileIconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            labelsStack.leadingAnchor.constraint(equalTo: fileIconView.trailingAnchor, constant: UX.labelsLeadingSpacing),
            labelsStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            labelsStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelsStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: UX.labelsVerticalInset),
            labelsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -UX.labelsVerticalInset),
        ])
    }
    
    func configure(fileURL: URL, byteCount: Int64?) {
        fileNameLabel.text = fileURL.lastPathComponent
        sizeLabel.text = byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        ?? NSLocalizedString("Unknown size", comment: "")
        
        if let thumbnailRequest {
            QLThumbnailGenerator.shared.cancel(thumbnailRequest)
        }
        fileIconView.image = UIImage(named: "reynard.document")
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL, size: UX.thumbnailSize, scale: UIScreen.main.scale, representationTypes: .icon
        )
        request.iconMode = true
        thumbnailRequest = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            DispatchQueue.main.async {
                guard let self, self.thumbnailRequest === request else {
                    return
                }
                if let thumbnail {
                    self.fileIconView.image = thumbnail.uiImage
                }
            }
        }
    }
}
