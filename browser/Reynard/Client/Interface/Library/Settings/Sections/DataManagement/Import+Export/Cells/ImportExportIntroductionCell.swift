//
//  ImportExportIntroductionCell.swift
//  Reynard
//
//  Created by Minh Ton on 22/10/26.
//

import UIKit

final class ImportExportIntroductionCell: UITableViewCell {
    private enum UX {
        static let iconSize: CGFloat = 48
        static let verticalInset: CGFloat = 16
        static let iconSpacing: CGFloat = 16
        static let textSpacing: CGFloat = 8
    }
    
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureViews()
        installViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureViews() {
        selectionStyle = .none
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .label
        
        titleLabel.font = UIFont(
            descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
                .withSymbolicTraits(.traitBold)!,
            size: 0
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits.insert(.header)
        
        descriptionLabel.font = .preferredFont(forTextStyle: .body)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.textAlignment = .center
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0
    }
    
    private func installViews() {
        let stackView = UIStackView(arrangedSubviews: [iconView, titleLabel, descriptionLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = UX.textSpacing
        stackView.setCustomSpacing(UX.iconSpacing, after: iconView)
        contentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: UX.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: UX.iconSize),
            titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            descriptionLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.verticalInset),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.verticalInset),
        ])
    }
    
    func configure(iconName: String, title: String, description: String) {
        iconView.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        titleLabel.text = title
        descriptionLabel.text = description
    }
}
